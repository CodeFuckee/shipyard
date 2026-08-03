#!/usr/bin/env node
/**
 * 登录页自动填充（vaultwarden/Bitwarden）复现/回归测试
 *
 * 真实运行 Flutter Web 登录页，验证影子登录表单（web/autofill_hints.js）：
 *   1. 页面任意时刻，DOM 中都存在可被密码管理器识别的完整登录表单
 *      （username + current-password 影子字段）
 *   2. 模拟 Bitwarden 填充影子字段后，值同步进入 Flutter 输入框
 *   3. 用户手动输入时，影子字段同步保持（供密码管理器读取）
 *   4. 无控制台异常
 *
 * 背景：Flutter Web 引擎（CanvasKit）在字段无 autofillHints 时，失焦即从
 * DOM 移除该字段元素（text_editing.dart disable() → safeRemove）。因此
 * 用户名/密码框无法同时在 DOM 中，Bitwarden 扩展填充时必然找不到某个字段，
 * 表现为"点击自动填充图标后值没填入"。修复方案见 web/autofill_hints.js。
 *
 * 运行前置：flutter build web 已执行。
 * 自动启动：内嵌静态服务器 + headless Chrome（CDP）。
 *
 * 用法: node tool/web_autofill_test.js
 * 退出码: 0 = 通过, 1 = 失败（复现 bug 或回归）
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn, execSync } = require('child_process');

const BUILD_DIR = path.join(__dirname, '..', 'build', 'web');
const PORT = 8123;
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const DEBUG_PORT = 9223;
const USER_DATA_DIR = '/tmp/chrome-autofill-test-' + DEBUG_PORT;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => console.log(...a);

// ---------- 内嵌静态文件服务器 ----------
function startServer() {
  const mime = { '.html': 'text/html', '.js': 'application/javascript', '.css': 'text/css', '.png': 'image/png', '.json': 'application/json', '.wasm': 'application/wasm', '.otf': 'font/otf', '.ttf': 'font/ttf', '.svg': 'image/svg+xml' };
  const server = http.createServer((req, res) => {
    let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (p === '/') p = '/index.html';
    const file = path.join(BUILD_DIR, p);
    if (!file.startsWith(BUILD_DIR) || !fs.existsSync(file)) {
      res.writeHead(404);
      res.end('not found');
      return;
    }
    res.writeHead(200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => {
    server.listen(PORT, '127.0.0.1', () => resolve(server));
  });
}

// ---------- CDP 客户端 ----------
function getJson(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => resolve(JSON.parse(data)));
    }).on('error', reject);
  });
}

async function connect() {
  let targets;
  for (let i = 0; i < 60; i++) {
    try {
      targets = await getJson(`http://127.0.0.1:${DEBUG_PORT}/json/list`);
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
  const consoleErrors = []; // 收集页面异常/console error
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    } else if (msg.method === 'Runtime.exceptionThrown') {
      consoleErrors.push('Uncaught: ' + (msg.params.exceptionDetails.exception?.description || msg.params.exceptionDetails.text));
    } else if (msg.method === 'Log.entryAdded' && msg.params.entry.level === 'error') {
      consoleErrors.push('console.error: ' + msg.params.entry.text);
    }
  };
  const send = (method, params = {}) =>
    new Promise((resolve) => {
      const mid = ++id;
      pending.set(mid, resolve);
      ws.send(JSON.stringify({ id: mid, method, params }));
    });
  const evalJs = async (expression) => {
    const res = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
    if (res.result?.exceptionDetails) {
      return { __exception: res.result.exceptionDetails.exception?.description || res.result.exceptionDetails.text };
    }
    return res.result?.result?.value;
  };
  const click = async (x, y) => {
    await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
    await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
  };
  return { send, evalJs, click, consoleErrors };
}

// 收集 DOM 中可被密码管理器识别的字段（Flutter 输入框 + 影子字段）
const COLLECT_FIELDS_JS = `(() => {
  const els = [...document.querySelectorAll('input')];
  const hasUsername = els.some((i) => i.getAttribute('autocomplete') === 'username');
  const hasPassword = els.some((i) => i.getAttribute('autocomplete') === 'current-password' || i.type === 'password');
  return { hasUsername, hasPassword, fields: els.map((i) => ({
    tag: i.tagName, type: i.type, autocomplete: i.getAttribute('autocomplete'), name: i.getAttribute('name'),
    id: i.id, value: i.value, isFlutter: i.classList.contains('flt-text-editing'),
  })) };
})()`;

// 模拟 Bitwarden 填充影子字段：赋值并派发 input/change 事件
const FILL_SHADOW_JS = `(() => {
  const user = document.getElementById('flt-shadow-username');
  const pass = document.getElementById('flt-shadow-password');
  const fill = (el, v) => {
    if (!el) return '字段不存在';
    el.value = v;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return 'OK';
  };
  return { userFill: fill(user, 'admin'), passFill: fill(pass, 'Passw0rd!') };
})()`;

// 读取 Flutter 输入框当前值（按身份:type/autocomplete 判断）
const FLUTTER_VALUES_JS = `(() => {
  const els = [...document.querySelectorAll('input.flt-text-editing')];
  const kind = (i) => i.type === 'password' || i.getAttribute('autocomplete') === 'current-password'
    ? 'password' : 'username';
  const u = els.find((i) => kind(i) === 'username');
  const p = els.find((i) => kind(i) === 'password');
  return { user: u ? u.value : null, pass: p ? p.value : null };
})()`;

// 用户输入模拟:给 Flutter 输入框写值并派发 input 事件
const TYPE_INTO_FLUTTER_JS = `(() => {
  const els = [...document.querySelectorAll('input.flt-text-editing')];
  const kind = (i) => i.type === 'password' || i.getAttribute('autocomplete') === 'current-password'
    ? 'password' : 'username';
  const u = els.find((i) => kind(i) === 'username');
  if (!u) return '无用户名框';
  u.value = 'myuser';
  u.dispatchEvent(new Event('input', { bubbles: true }));
  return 'OK';
})()`;

let failures = 0;
function check(cond, name, detail) {
  if (cond) {
    log(`  ✅ ${name}`);
  } else {
    failures++;
    log(`  ❌ ${name}`);
    if (detail) log(`     详情: ${JSON.stringify(detail)}`);
  }
}

async function waitFor(evalJs, expr, timeoutMs = 5000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await evalJs(expr)) return true;
    await sleep(200);
  }
  return false;
}

async function main() {
  log('[*] 启动静态服务器...');
  const server = await startServer();
  log(`[*] 启动 headless Chrome (port ${DEBUG_PORT})...`);
  execSync('pkill -f "remote-debugging-port=' + DEBUG_PORT + '" >/dev/null 2>&1 || true');
  const chrome = spawn(CHROME, [
    '--headless=new', '--disable-gpu', `--remote-debugging-port=${DEBUG_PORT}`,
    `--user-data-dir=${USER_DATA_DIR}`, 'about:blank',
  ], { stdio: 'ignore' });
  await sleep(2000);
  const { evalJs, click, send, consoleErrors } = await connect();
  await send('Runtime.enable');
  await send('Log.enable');
  await evalJs('window.location.href = "http://127.0.0.1:' + PORT + '/"');

  // 等待 Flutter 加载
  for (let i = 0; i < 60; i++) {
    const ready = await evalJs(`!!document.querySelector('flt-text-editing-host')`);
    if (ready) break;
    await sleep(500);
  }
  await sleep(3000); // 登录页渲染 + autofocus

  log('\n[测试1] 初始状态:完整登录表单始终可被密码管理器识别');
  let fields = await evalJs(COLLECT_FIELDS_JS);
  check(fields.hasUsername && fields.hasPassword, 'DOM 中存在 username + password 字段（影子表单）', fields.fields);

  log('\n[测试2] 模拟用户点击密码框后,完整表单仍可识别');
  const rect = await evalJs(`(() => {
    const u = document.querySelector('input.flt-text-editing');
    if (!u) return null;
    const r = u.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + 84 };
  })()`);
  if (rect) await click(rect.x, rect.y);
  await sleep(1000);
  fields = await evalJs(COLLECT_FIELDS_JS);
  check(fields.hasUsername && fields.hasPassword, 'DOM 中同时存在 username + password 字段', fields.fields);
  const afterPassClick = await evalJs(FLUTTER_VALUES_JS);
  check(afterPassClick.pass !== null, '密码框已聚焦（Flutter 创建了密码输入框）', afterPassClick);

  log('\n[测试3] 模拟 Bitwarden 点击填充(填充影子字段)');
  const fill = await evalJs(FILL_SHADOW_JS);
  check(fill.userFill === 'OK' && fill.passFill === 'OK', '影子字段填充成功', fill);
  // 等待同步尝试完成(同步可能立即生效,也可能失败交给聚焦补写兜底)
  await sleep(3000);
  // 模拟真实用户:点击用户名框聚焦 → 值应出现(立即同步或聚焦补写)
  await click(390, 238);
  await sleep(1000);
  const userValAfter3a = await evalJs(FLUTTER_VALUES_JS);
  check(userValAfter3a.user === 'admin', '用户名 admin 已进入 Flutter（立即同步或聚焦补写）', userValAfter3a);
  // 模拟真实用户:点击密码框聚焦 → 密码值应出现(立即同步或聚焦补写)
  await click(390, 302);
  await sleep(1000);
  const passVal = await evalJs(FLUTTER_VALUES_JS);
  check(passVal.pass === 'Passw0rd!', '密码 Passw0rd! 已进入 Flutter（立即同步或聚焦补写）', passVal);

  log('\n[测试4] 用户手动输入时,影子字段同步(供密码管理器读取)');
  await click(390, 238); // 聚焦用户名框
  await sleep(800);
  const typed = await evalJs(TYPE_INTO_FLUTTER_JS);
  check(typed === 'OK', '向 Flutter 用户名框输入 myuser');
  const shadowSynced = await waitFor(evalJs, `(() => {
    const s = document.getElementById('flt-shadow-username');
    return !!s && s.value === 'myuser';
  })()`, 3000);
  check(shadowSynced, '影子用户名字段同步为 myuser');

  log('\n[测试5] 回点用户名框后,完整表单仍可识别');
  if (rect) await click(rect.x, rect.y - 64);
  await sleep(800);
  fields = await evalJs(COLLECT_FIELDS_JS);
  check(fields.hasUsername && fields.hasPassword, 'DOM 中同时存在 username + password 字段', fields.fields);

  if (consoleErrors.length) {
    log('\n[控制台] 页面执行期间出现异常:');
    consoleErrors.forEach((e) => log('  ⚠️  ' + e));
    check(false, '页面无控制台异常', consoleErrors);
  } else {
    log('\n[控制台] 无异常 ✅');
  }

  chrome.kill();
  server.close();
  if (failures > 0) {
    log(`\n✗ 测试失败: ${failures} 个断言未通过`);
    process.exit(1);
  }
  log('\n✓ 全部断言通过');
  process.exit(0);
}

main().catch((e) => {
  console.error('测试执行失败:', e);
  process.exit(1);
});
