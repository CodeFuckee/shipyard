#!/usr/bin/env node
/**
 * Web 自动填充行为探针（Chrome headless + CDP）
 *
 * 用途：真实运行 Flutter Web 登录页，观察：
 *   1. 聚焦用户名/密码框时，引擎在 DOM 中创建的 input 元素及其属性
 *   2. 模拟 Bitwarden/Vaultwarden 扩展的填充动作后，值是否进入 Flutter
 *
 * 前置：
 *   1. flutter build web 已执行
 *   2. 构建产物已通过 http server 提供（如: cd build/web && python3 -m http.server 8080）
 *   3. Chrome 已以 --remote-debugging-port=9222 启动
 *
 * 用法: node tool/web_autofill_probe.js [pageUrl]
 */
const http = require('http');

const PAGE_URL = process.argv[2] || 'http://localhost:8080/';
const DEBUG_WS = 'http://127.0.0.1:9222/json/list';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function getJson(url) {
  return new Promise((resolve, reject) => {
    http
      .get(url, (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => resolve(JSON.parse(data)));
      })
      .on('error', reject);
  });
}

async function connect() {
  let targets;
  for (let i = 0; i < 60; i++) {
    try {
      targets = await getJson(DEBUG_WS);
      if (targets.length) break;
    } catch (_) {}
    await sleep(500);
  }
  const page = targets.find((t) => t.type === 'page');
  if (!page) throw new Error('未找到 Chrome 页面 target');
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r, j) => {
    ws.onopen = r;
    ws.onerror = j;
  });
  let id = 0;
  const pending = new Map();
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    }
  };
  const send = (method, params = {}) =>
    new Promise((resolve) => {
      const mid = ++id;
      pending.set(mid, resolve);
      ws.send(JSON.stringify({ id: mid, method, params }));
    });
  const evalJs = async (expression) => {
    const res = await send('Runtime.evaluate', {
      expression,
      returnByValue: true,
      awaitPromise: true,
    });
    if (res.result?.exceptionDetails) {
      return { __exception: res.result.exceptionDetails.text, __detail: res.result.exceptionDetails.exception?.description };
    }
    return res.result?.result?.value;
  };
  return { send, evalJs };
}

// 汇总 DOM 中所有 Flutter 文本编辑元素的信息
const DUMP_JS = `(() => {
  const collect = (el) => {
    const r = el.getBoundingClientRect();
    return {
      tag: el.tagName,
      type: el.type,
      autocomplete: el.getAttribute('autocomplete'),
      name: el.getAttribute('name'),
      className: el.className,
      value: el.value,
      rect: { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) },
      inDom: el.isConnected,
    };
  };
  return {
    inputs: [...document.querySelectorAll('input')].map(collect),
    textareas: [...document.querySelectorAll('textarea')].map(collect),
  };
})()`;

// 模拟 Bitwarden 扩展填充：按 autocomplete/type 匹配字段，赋值并派发 input/change 事件
const FILL_JS = `(() => {
  const els = [...document.querySelectorAll('input')];
  const user = els.find((i) => i.getAttribute('autocomplete') === 'username');
  const pass = els.find((i) => i.getAttribute('autocomplete') === 'current-password' || i.type === 'password');
  const fill = (el, v) => {
    if (!el) return '字段不存在';
    el.focus();
    el.value = v;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return '已填充 value=' + v;
  };
  return {
    foundUser: !!user,
    foundPass: !!pass,
    userResult: fill(user, 'admin'),
    passResult: fill(pass, 'Passw0rd!'),
    after: [...document.querySelectorAll('input')].map((i) => ({
      tag: i.tagName, type: i.type, autocomplete: i.getAttribute('autocomplete'), value: i.value,
    })),
  };
})()`;

async function main() {
  const { send, evalJs } = await connect();
  await send('Page.enable');
  await send('Runtime.enable');
  await send('Page.navigate', { url: PAGE_URL });
  console.log('[*] 已导航到', PAGE_URL);

  // 等待 Flutter 加载（文本编辑 host 出现）
  for (let i = 0; i < 60; i++) {
    const ready = await evalJs(`!!document.querySelector('flt-text-editing-host') || !!document.querySelector('flutter-view')`);
    if (ready) break;
    await sleep(500);
  }
  await sleep(3000); // 等待登录页渲染 + autofocus 生效
  console.log('[*] Flutter 已加载，登录页渲染完成\n');

  const dump = async (label, n) => {
    const d = await evalJs(DUMP_JS);
    console.log(`--- ${label} ---`);
    console.log(JSON.stringify(d, null, 2));
    const shot = await send('Page.captureScreenshot', { format: 'png' });
    require('fs').writeFileSync(`/tmp/autofill_step${n}.png`, Buffer.from(shot.result.data, 'base64'));
    console.log(`    截图: /tmp/autofill_step${n}.png\n`);
  };

  const click = async (x, y) => {
    await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
    await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
  };

  // 1) 初始状态（用户名框 autofocus）
  await dump('初始状态', 1);

  // 2) 真实点击密码框（用户名框 rect 为 x=222,y=226,w=336,h=24，
  //    密码框在其下方约 72px：y≈298，取字段中心 y≈310）
  //    先从 DOM 读取用户名框 rect 推算密码框坐标
  const rect = await evalJs(`(() => {
    const u = document.querySelector('input');
    if (!u) return null;
    const r = u.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + 84 };
  })()`);
  console.log('[ ] 推算密码框点击坐标:', rect);
  if (rect) await click(rect.x, rect.y);
  await sleep(1000);
  await dump('点击密码框后', 2);

  // 3) 模拟 Bitwarden 填充（此时应存在 password 字段）
  const fillResult = await evalJs(FILL_JS);
  console.log('--- 模拟 Bitwarden 填充 ---');
  console.log(JSON.stringify(fillResult, null, 2));
  await sleep(800);
  await dump('填充后', 3);

  // 4) 点击用户名框，观察旧元素是否保留
  if (rect) await click(rect.x, rect.y - 84);
  await sleep(800);
  await dump('回点击用户名框后', 4);

  console.log('[*] 探针完成');
  process.exit(0);
}

main().catch((e) => {
  console.error('探针失败:', e);
  process.exit(1);
});
