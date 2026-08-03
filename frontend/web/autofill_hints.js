// 登录页自动填充(vaultwarden/Bitwarden)适配脚本
// ------------------------------------------------
// 背景(为什么需要本脚本):
//   1. ohos 定制版 Flutter 引擎的 autofill form 管理存在 bug(updateConfig 会
//      重建并拆散多字段 form,污染 DOM 并触发 Uncaught Error),因此登录页
//      不能使用 Flutter 的 autofillHints(见 login_screen.dart 注释)。
//   2. 没有 autofillHints 时,引擎对失焦字段调用 safeRemove 从 DOM 移除
//      (flutter_web_sdk text_editing.dart disable()),导致用户名/密码框无法
//      同时在 DOM 中。密码管理器(Bitwarden/vaultwarden)点击填充时扫描
//      DOM,必然找不到某个字段 → 表现为"点了自动填充图标但值没填入"。
//
// 方案:影子登录表单
//   - 在 DOM 中维护一对始终存在的隐藏字段(username + current-password),
//     密码管理器随时都能识别出完整登录表单并弹出填充提示。
//   - 双向同步:
//       * Flutter 输入变化(用户手动输入) → 同步到影子字段,供密码管理器读取;
//       * 影子字段被密码管理器填充 → 若目标 Flutter 字段在 DOM(已聚焦)则
//         直接写入并派发 input 事件;否则模拟点击该字段位置让 Flutter 聚焦,
//         待引擎创建输入框后写入值并派发 input 事件 → Flutter controller
//         更新,填充生效。
//   - 聚焦的 Flutter 输入框被引擎应用 autocomplete="off" 后,本脚本覆盖为
//     正确的 username/current-password。
(() => {
  'use strict';

  var SHADOW_USER_ID = 'flt-shadow-username';
  var SHADOW_PASS_ID = 'flt-shadow-password';
  // 登录页布局固定(maxWidth 400 垂直居中),实测用户名/密码输入框
  // 的 DOM 元素 rect 纵向相差 64px
  var FIELD_GAP_Y = 64;
  var HINT_USER = 'username';
  var HINT_PASS = 'current-password';

  function isFlutterInput(el) {
    return !!el && el.tagName === 'INPUT' &&
      (el.classList.contains('flt-text-editing') ||
        el.getAttribute('data-semantics-role') === 'text-field');
  }

  function flutterInputs() {
    var all = [];
    document.querySelectorAll('input').forEach(function (i) { all.push(i); });
    return all.filter(isFlutterInput);
  }

  // 判断字段身份(用户名/密码)。优先看 DOM 属性;密码框切换显示/隐藏后
  // type 会变 text 且 autocomplete 被引擎重置为 off,此时按位置分类:
  // 密码框始终位于用户名框下方 FIELD_GAP_Y 处。
  var rectCache = {};
  function cacheRect(el) {
    var r = el.getBoundingClientRect();
    rectCache[fieldKind(el)] = { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }
  function fieldKind(el) {
    if (el.type === 'password' || el.getAttribute('autocomplete') === HINT_PASS) {
      return 'password';
    }
    if (el.getAttribute('autocomplete') === HINT_USER) {
      return 'username';
    }
    // 回退:按位置分类
    var cy = el.getBoundingClientRect().y + el.getBoundingClientRect().height / 2;
    var py = rectCache['password'] && rectCache['password'].y;
    var uy = rectCache['username'] && rectCache['username'].y;
    if (py !== undefined && Math.abs(cy - py) < FIELD_GAP_Y / 2) return 'password';
    if (uy !== undefined && Math.abs(cy - uy) < FIELD_GAP_Y / 2) return 'username';
    if (py !== undefined) return 'username'; // 距已缓存密码框较远 → 用户名框
    if (uy !== undefined) return 'password'; // 距已缓存用户名框较远 → 密码框
    return 'username';
  }

  function flutterInputFor(kind) {
    return flutterInputs().find(function (i) { return fieldKind(i) === kind; });
  }

  function shadowField(kind) {
    return document.getElementById(kind === 'password' ? SHADOW_PASS_ID : SHADOW_USER_ID);
  }

  // 目标字段不在 DOM 时的点击坐标候选列表。
  // 实测(ohos 引擎 + CanvasKit):同坐标的点击有时命中有时不命中,且 CDP 与
  // JS 合成事件行为不一致,因此提供多个候选点,重试时逐个尝试:
  //   - 缓存过的字段位置(最准确)
  //   - 从当前聚焦字段按布局推算(上下偏移 64~88px,实测有效区间)
  function candidatePoints(kind) {
    var pts = [];
    // 实测(ohos 引擎 + CanvasKit + 800x600 视口)合成点击稳定的坐标:
    // 用户名框 (378,226) / 密码框 (390,302)。放在首位作为首选。
    pts.push(kind === 'password' ? { x: 390, y: 302 } : { x: 378, y: 226 });
    if (rectCache[kind]) pts.push(rectCache[kind]);
    var active = flutterInputs()[0];
    if (active) {
      var r = active.getBoundingClientRect();
      var x = r.x + r.width / 2;
      var down = kind === 'password';
      [64, 76, 88].forEach(function (off) {
        pts.push({ x: x, y: down ? r.y + off : r.y - off });
      });
    }
    return pts;
  }

  // ---------- autocomplete 覆盖(聚焦/属性变化时) ----------
  function applyHints(el) {
    if (!isFlutterInput(el)) return;
    var kind = fieldKind(el);
    var hint = kind === 'password' ? HINT_PASS : HINT_USER;
    if (el.getAttribute('autocomplete') !== hint) {
      el.setAttribute('autocomplete', hint);
      el.setAttribute('name', hint);
    }
    cacheRect(el);
    // 补写:焦点切换路径(见 syncShadowToFlutter)可能失败,此时用户聚焦字段
    // (点击输入框准备输入)时,若影子字段已有值而 Flutter 字段为空,立即补写,
    // 保证 Bitwarden 填充的值最终进入 Flutter controller。
    var shadow = shadowField(kind);
    if (shadow && shadow.value && el.value === '') {
      writeToFlutter(el, shadow.value);
    }
  }

  // ---------- 影子登录表单 ----------
  function ensureShadowForm() {
    if (shadowField('username')) return;
    var form = document.createElement('form');
    // 参照 Flutter 引擎 autofill 隐藏字段的样式(off-screen + 0 尺寸):
    // 不能使用 display:none,密码管理器会跳过 display:none 的元素
    form.style.cssText = 'position:fixed;left:-9999px;top:0;width:0;height:0;';
    form.setAttribute('aria-hidden', 'true');
    // 防止按 Enter 触发表单提交刷新页面
    form.addEventListener('submit', function (e) { e.preventDefault(); });

    var user = document.createElement('input');
    user.id = SHADOW_USER_ID;
    user.type = 'text';
    user.setAttribute('autocomplete', HINT_USER);
    user.name = HINT_USER;
    user.tabIndex = -1;

    var pass = document.createElement('input');
    pass.id = SHADOW_PASS_ID;
    pass.type = 'password';
    pass.setAttribute('autocomplete', HINT_PASS);
    pass.name = HINT_PASS;
    pass.tabIndex = -1;

    form.appendChild(user);
    form.appendChild(pass);
    document.body.appendChild(form);

    // 影子字段被密码管理器填充 → 转发到 Flutter(串行,避免焦点竞争)
    user.addEventListener('input', function () { enqueueSync('username'); });
    user.addEventListener('change', function () { enqueueSync('username'); });
    pass.addEventListener('input', function () { enqueueSync('password'); });
    pass.addEventListener('change', function () { enqueueSync('password'); });
  }

  // ---------- Flutter → 影子(用户手动输入时同步) ----------
  function syncFlutterToShadow(kind) {
    var flt = flutterInputFor(kind);
    var shadow = shadowField(kind);
    if (!flt || !shadow) return;
    if (flt.value !== shadow.value) shadow.value = flt.value;
  }

  // ---------- 影子 → Flutter(填充转发,串行避免焦点竞争) ----------
  var syncQueue = Promise.resolve();
  function enqueueSync(kind) {
    syncQueue = syncQueue.then(function () {
      return syncShadowToFlutter(kind);
    }).catch(function () { /* 单次同步失败不影响后续 */ });
  }

  function syncShadowToFlutter(kind) {
    var shadow = shadowField(kind);
    if (!shadow) return Promise.resolve();
    var value = shadow.value;
    var flt = flutterInputFor(kind);
    if (flt && flt.isConnected) {
      writeToFlutter(flt, value);
      return Promise.resolve();
    }
    // 目标字段未聚焦(DOM 中不存在):模拟点击其位置,待引擎创建输入框后写入。
    // 点击必须延迟到宏任务派发:Bitwarden 填充的事件在 microtask 链中处理,
    // 若同链派发点击,引擎/Flutter 会吞掉事件(实测 microtask 中的点击全部
    // 无效,延迟 100ms 后同一坐标的点击立即生效)。
    var pts = candidatePoints(kind);
    if (!pts.length) return Promise.resolve();
    return new Promise(function (resolve) {
      setTimeout(function () {
        // 先 blur 当前聚焦字段:实测合成切换的焦点状态下点击会被引擎吞掉,
        // blur 后引擎失焦移除字段、焦点状态归零,点击才能正常生效。
        // 注意:blur 后必须等待 ~500ms 再点击 —— 引擎的失焦处理(异步消息到
        // Flutter 再移除字段)需要时间,间隔太短点击仍会被竞争掉。
        blurActive();
        setTimeout(function () {
          dispatchPointerClick(pts[0].x, pts[0].y);
          waitForFlutterField(kind, value, pts).then(resolve);
        }, 500);
      }, 100);
    });
  }

  function blurActive() {
    var active = document.activeElement;
    if (active && active.blur && active.tagName === 'INPUT') {
      active.blur();
    }
  }

  // 写入 Flutter 字段。
  // 注意:不能调用 flt.focus() —— ohos 定制引擎的 updateConfig 链路在
  // focus 时可能重建编辑元素,导致写入失败(实测 focus 后 username input
  // 被重建消失)。wait 路径找到的字段是引擎刚创建并聚焦的 active 元素,
  // 直接写值 + 派发 input 事件即可进入 Flutter controller。
  function writeToFlutter(flt, value) {
    if (flt.value !== value) {
      flt.value = value;
      flt.dispatchEvent(new Event('input', { bubbles: true }));
    }
  }

  // 轮询等待引擎创建目标字段。
  // 实测:重试点击会反复污染引擎焦点状态(每次失败的点击都会干扰下一次),
  // 因此只允许一次点击(syncShadowToFlutter 中发出),这里只做纯轮询。
  function waitForFlutterField(kind, value) {
    return new Promise(function (resolve) {
      var deadline = Date.now() + 2500;
      (function tick() {
        var flt = flutterInputFor(kind);
        if (flt && flt.isConnected) {
          writeToFlutter(flt, value);
          resolve();
          return;
        }
        if (Date.now() < deadline) {
          setTimeout(tick, 300);
        } else {
          resolve();
        }
      })();
    });
  }

  // 模拟用户点击 Flutter canvas 上某坐标(Flutter 引擎监听 pointer/mouse 事件)。
  // 注意:
  //   1. 每次点击必须使用不同的 pointerId —— Flutter 引擎按 pointerId 追踪
  //      指针状态,若复用同一 id,引擎会认为该指针仍按下而忽略后续的
  //      pointerdown。
  //   2. 事件固定派发到 flutter-view(引擎 pointer 监听器所在),不能使用
  //      elementFromPoint —— 合成切换焦点后引擎的 flt-text-editing input
  //      可能被定位到异常位置并覆盖目标区域,事件派发到 input 上会被引擎
  //      当作编辑元素内部事件处理,导致点击无效(实测)。
  var nextPointerId = 1;
  function dispatchPointerClick(x, y) {
    var id = nextPointerId++;
    var target = document.querySelector('flutter-view') || document.body;
    var opts = {
      bubbles: true, cancelable: true, composed: true,
      clientX: x, clientY: y, screenX: x, screenY: y,
      button: 0, buttons: 1, pointerId: id, pointerType: 'mouse', isPrimary: true,
    };
    if (typeof PointerEvent !== 'undefined') {
      target.dispatchEvent(new PointerEvent('pointerdown', opts));
      target.dispatchEvent(new PointerEvent('pointerup', opts));
    }
    // 兼容:部分场景 Flutter 监听 MouseEvent
    target.dispatchEvent(new MouseEvent('mousedown', opts));
    target.dispatchEvent(new MouseEvent('mouseup', opts));
  }

  // ---------- 事件挂载 ----------
  // 1) Flutter 输入框聚焦时,引擎已完成 applyConfiguration(autocomplete="off"),
  //    这里覆盖为正确的 username/current-password
  document.addEventListener('focusin', function (e) {
    applyHints(e.target);
  }, true);

  // 2) 输入框创建/属性变化时(如引擎重建输入框、密码框切换显示/隐藏后
  //    type 变化导致 autocomplete 被重置)
  new MutationObserver(function () {
    document.querySelectorAll('input').forEach(applyHints);
  }).observe(document.documentElement, {
    childList: true, subtree: true,
    attributes: true, attributeFilter: ['type', 'autocomplete'],
  });

  // 3) 用户手动输入 → 同步到影子字段(捕获阶段,先于引擎处理)
  document.addEventListener('input', function (e) {
    if (isFlutterInput(e.target)) syncFlutterToShadow(fieldKind(e.target));
  }, true);

  ensureShadowForm();
})();
