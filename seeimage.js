/*!
 * seeimage.js — 网页版图片查看器（单文件、零依赖）
 * ---------------------------------------------------------------------------
 * 从「上门超人」macOS 客户端的原生预览窗口（ZoomableImageView +
 * ImagePreviewController）逐条移植而来：缩放、平移、旋转、左右翻转、图集翻页、
 * 拖拽接收、存储图片、浏览器打开原图，交互和快捷键都保持一致。
 *
 * 用法一：引入后直接打开一组图片
 *   <script src="seeimage.js"></script>
 *   SeeImage.open(["a.jpg", "b.jpg"], 0);
 *
 * 用法二：页面里的图片点一下就打开（同一个 [data-seeimage-gallery] 内自动成组）
 *   <div data-seeimage-gallery>
 *     <img src="a.jpg"><img src="b.jpg"><img src="c.jpg">
 *   </div>
 *   SeeImage.bind(document, "img");
 *
 * 也可以在图片上直接写 data-seeimage="原图地址"，用来让缩略图指向大图：
 *   <img src="thumb.jpg" data-seeimage="large.jpg">
 *
 * 快捷键：← → 翻页 · + - 缩放 · 0 适应窗口 · r 右转 · R 左转 · F 翻转 ·
 *         ⌘S 存储 · Esc 关闭
 * ---------------------------------------------------------------------------
 */
(function (global) {
  "use strict";

  if (global.SeeImage && global.SeeImage.version) return;

  var MIN_ZOOM = 0.2;
  var MAX_ZOOM = 8;
  var CONTENT_INSET = 30; // 图片与画布边缘留白（同原生 contentInset）
  var SWIPE_THRESHOLD = 70; // 横向拖拽超过这个距离就翻页
  var RUBBER_BAND = 0.22; // 适应窗口时拖拽的跟随比例

  /* ------------------------------------------------------------------ *
   * 小工具
   * ------------------------------------------------------------------ */

  function clamp(value, min, max) {
    return Math.min(Math.max(value, min), max);
  }

  function fileNameFromURL(url) {
    try {
      var parsed = new URL(url, location.href);
      var name = decodeURIComponent(parsed.pathname.split("/").pop() || "");
      if (name) return name;
    } catch (error) {
      /* blob: / data: 之类没有路径，退回到下面的兜底 */
    }
    if (url.indexOf("data:") === 0) return "image.png";
    return "image.png";
  }

  function normalizeItems(list) {
    var input = Array.isArray(list) ? list : [list];
    var items = [];
    for (var i = 0; i < input.length; i++) {
      var entry = input[i];
      if (!entry) continue;
      if (typeof entry === "string") {
        items.push({ url: entry, name: fileNameFromURL(entry) });
      } else if (entry.url || entry.src) {
        var url = entry.url || entry.src;
        items.push({ url: url, name: entry.name || fileNameFromURL(url) });
      }
    }
    return items;
  }

  function urlOfNode(node) {
    if (!node) return "";
    if (node.tagName === "IMG") return node.currentSrc || node.src || "";
    var attr = node.getAttribute("data-seeimage");
    if (attr && attr !== "true" && attr !== "") return attr;
    return node.getAttribute("href") || "";
  }

  /* ------------------------------------------------------------------ *
   * 样式：内嵌在 Shadow DOM 里，不会和宿主页面互相污染
   * ------------------------------------------------------------------ */

  var STYLE = [
    ":host { all: initial; }",
    "*, *::before, *::after { box-sizing: border-box; }",
    ".root {",
    "  position: fixed; inset: 0; z-index: 2147483000;",
    "  display: flex; align-items: center; justify-content: center;",
    "  padding: 24px; background: rgba(18, 18, 20, 0.44);",
    "  -webkit-backdrop-filter: blur(4px); backdrop-filter: blur(4px);",
    "  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC',",
    "    'Hiragino Sans GB', 'Microsoft YaHei', sans-serif;",
    "  color: #1d1d1f; -webkit-font-smoothing: antialiased;",
    "  animation: fade 0.16s ease-out;",
    "}",
    "@keyframes fade { from { opacity: 0 } to { opacity: 1 } }",
    ".window {",
    "  position: relative; display: flex; flex-direction: column;",
    "  width: min(1120px, 92vw); height: min(820px, 88vh);",
    "  background: #ffffff; border-radius: 14px; overflow: hidden;",
    "  box-shadow: 0 40px 90px rgba(0, 0, 0, 0.34), 0 0 0 0.5px rgba(0, 0, 0, 0.18);",
    "  animation: rise 0.2s cubic-bezier(0.22, 0.61, 0.36, 1);",
    "}",
    "@keyframes rise { from { opacity: 0; transform: translateY(8px) scale(0.995) } to { opacity: 1; transform: none } }",
    ".titlebar { flex: 0 0 auto; display: flex; align-items: center; gap: 10px; height: 40px; padding: 0 16px; }",
    ".dots { display: flex; gap: 8px; }",
    ".dot { width: 12px; height: 12px; border-radius: 50%; box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.16); }",
    ".dot.close { background: #ff5f57; cursor: pointer; }",
    ".dot.close:hover { filter: brightness(1.06); }",
    ".dot.min { background: #febc2e; }",
    ".dot.max { background: #28c840; }",
    ".title { margin-left: 2px; font-size: 13px; font-weight: 500; color: #3a3a3c; letter-spacing: 0.1px; }",
    ".bar { flex: 0 0 auto; display: flex; flex-direction: column; gap: 14px; padding: 10px 28px 0; }",
    ".row { display: flex; align-items: center; gap: 12px; }",
    ".row.center { justify-content: center; }",
    ".row.split { justify-content: space-between; }",
    ".group { display: flex; align-items: center; gap: 12px; }",
    ".pill {",
    "  display: inline-flex; align-items: center; justify-content: center;",
    "  height: 34px; padding: 0 17px; border: 0; border-radius: 11px;",
    "  background: rgba(0, 0, 0, 0.055); color: #1d1d1f;",
    "  font: inherit; font-size: 14px; font-weight: 500; line-height: 1;",
    "  white-space: nowrap; cursor: pointer; -webkit-user-select: none; user-select: none;",
    "  transition: background-color 0.12s ease, color 0.12s ease;",
    "}",
    ".pill:hover { background: rgba(0, 0, 0, 0.09); }",
    ".pill:active { background: rgba(0, 0, 0, 0.14); }",
    ".pill:disabled { background: rgba(0, 0, 0, 0.03); color: rgba(0, 0, 0, 0.28); cursor: default; }",
    ".pill:focus-visible { outline: 2px solid #0a84ff; outline-offset: 2px; }",
    ".status { display: flex; align-items: center; gap: 14px; font-size: 13px; font-weight: 500; color: #6e6e73; font-variant-numeric: tabular-nums; }",
    ".canvas { position: relative; flex: 1 1 auto; overflow: hidden; touch-action: none; cursor: grab; }",
    ".canvas.dragging { cursor: grabbing; }",
    ".photo {",
    "  position: absolute; left: 50%; top: 50%; width: auto; height: auto;",
    "  max-width: none; max-height: none; border-radius: 10px;",
    "  transform-origin: 50% 50%; will-change: transform;",
    "  box-shadow: 0 18px 44px rgba(0, 0, 0, 0.22); background: #fff;",
    "  -webkit-user-drag: none; user-select: none; pointer-events: none;",
    "  image-rendering: auto;",
    "}",
    ".photo.anim { transition: transform 0.22s cubic-bezier(0.22, 0.61, 0.36, 1); }",
    ".photo.hidden { visibility: hidden; }",
    ".state {",
    "  position: absolute; inset: 0; display: none; flex-direction: column;",
    "  align-items: center; justify-content: center; gap: 10px; text-align: center;",
    "  color: #6e6e73; font-size: 13px; padding: 24px;",
    "}",
    ".state.visible { display: flex; }",
    ".state .headline { font-size: 15px; font-weight: 600; color: #3a3a3c; }",
    ".state .hint { max-width: 320px; line-height: 1.6; }",
    ".spinner {",
    "  width: 22px; height: 22px; border-radius: 50%;",
    "  border: 2px solid rgba(0, 0, 0, 0.12); border-top-color: #0a84ff;",
    "  animation: spin 0.7s linear infinite;",
    "}",
    "@keyframes spin { to { transform: rotate(360deg); } }",
    ".state .pill { margin-top: 4px; }",
    ".drop {",
    "  position: absolute; inset: 8px; border-radius: 10px; pointer-events: none;",
    "  border: 2px dashed #0a84ff; opacity: 0; transition: opacity 0.12s ease;",
    "}",
    ".root.dropping .drop { opacity: 1; }",
    "@media (max-width: 760px) {",
    "  .root { padding: 0; }",
    "  .window { width: 100%; height: 100%; border-radius: 0; }",
    "  .bar { padding: 8px 12px 0; gap: 10px; }",
    "  .row { flex-wrap: wrap; gap: 8px; }",
    "  .row.center { justify-content: center; }",
    "  .row.split { align-items: flex-start; }",
    "  .group { flex-wrap: wrap; gap: 8px; }",
    "  .status { width: 100%; justify-content: flex-end; font-size: 12px; gap: 10px; }",
    "  .pill { height: 32px; padding: 0 12px; font-size: 13px; border-radius: 10px; }",
    "  .titlebar { height: 36px; padding: 0 12px; }",
    "}",
  ].join("\n");

  /* ------------------------------------------------------------------ *
   * 查看器
   * ------------------------------------------------------------------ */

  function Viewer(items, startIndex, options) {
    this.items = items;
    this.index = items.length ? clamp(startIndex, 0, items.length - 1) : 0;
    this.options = options || {};
    this.rotation = 0; // 四分之一圈为单位
    this.flipped = false;
    this.zoom = 1; // 相对「适应窗口」的倍数，1 即 100%
    this.fitScale = 1;
    this.offset = { x: 0, y: 0 };
    this.natural = { width: 0, height: 0 };
    this.loading = false;
    this.error = false;
    this.loadToken = 0;

    this.build();
    this.bindEvents();
    this.refresh();
    this.loadCurrent(true);
    this.layout();
  }

  Viewer.prototype.build = function () {
    var host = document.createElement("div");
    host.className = "seeimage-host";
    host.style.cssText = "position:fixed;inset:0;width:0;height:0;";
    var shadow = host.attachShadow({ mode: "open" });

    var style = document.createElement("style");
    style.textContent = STYLE;
    shadow.appendChild(style);

    var root = document.createElement("div");
    root.className = "root";
    root.setAttribute("role", "dialog");
    root.setAttribute("aria-modal", "true");
    root.setAttribute("aria-label", "图片预览");
    root.innerHTML = [
      '<div class="window">',
      '  <div class="titlebar">',
      '    <div class="dots">',
      '      <span class="dot close" title="关闭" role="button" aria-label="关闭"></span>',
      '      <span class="dot min" aria-hidden="true"></span>',
      '      <span class="dot max" aria-hidden="true"></span>',
      "    </div>",
      '    <div class="title"></div>',
      "  </div>",
      '  <div class="bar">',
      '    <div class="row center">',
      '      <button type="button" class="pill" data-act="prev">‹ 上一张</button>',
      '      <button type="button" class="pill" data-act="next">下一张 ›</button>',
      '      <button type="button" class="pill" data-act="rotate-left">↺ 左转</button>',
      '      <button type="button" class="pill" data-act="rotate-right">↻ 右转</button>',
      '      <button type="button" class="pill" data-act="flip">↔ 左右翻转</button>',
      "    </div>",
      '    <div class="row split">',
      '      <div class="group">',
      '        <button type="button" class="pill" data-act="zoom-out">− 缩小</button>',
      '        <button type="button" class="pill" data-act="zoom-in">+ 放大</button>',
      '        <button type="button" class="pill" data-act="fit">适应窗口</button>',
      '        <button type="button" class="pill" data-act="open">浏览器打开原图</button>',
      '        <button type="button" class="pill" data-act="save">存储图片…</button>',
      "      </div>",
      '      <div class="status">',
      '        <span class="counter"></span>',
      '        <span class="percent"></span>',
      "      </div>",
      "    </div>",
      "  </div>",
      '  <div class="canvas">',
      '    <img class="photo hidden" alt="">',
      '    <div class="drop"></div>',
      '    <div class="state empty">',
      '      <div class="headline">把图片拖进来</div>',
      '      <div class="hint">支持本地文件，也支持网页里的图片链接</div>',
      '    </div>',
      '    <div class="state loading"><div class="spinner"></div><div>正在加载…</div></div>',
      '    <div class="state error">',
      '      <div class="headline">图片加载失败</div>',
      '      <div class="hint">检查文件是否仍然存在，或者网络是否正常</div>',
      '      <button type="button" class="pill" data-act="retry">重试</button>',
      "    </div>",
      "  </div>",
      "</div>",
    ].join("\n");

    shadow.appendChild(root);
    document.body.appendChild(host);

    this.host = host;
    this.root = root;
    this.photo = root.querySelector(".photo");
    this.canvas = root.querySelector(".canvas");
    this.title = root.querySelector(".title");
    this.counter = root.querySelector(".counter");
    this.percent = root.querySelector(".percent");
    this.buttons = {};
    var nodes = root.querySelectorAll("[data-act]");
    for (var i = 0; i < nodes.length; i++) {
      this.buttons[nodes[i].getAttribute("data-act")] = nodes[i];
    }
    this.emptyState = root.querySelector(".state.empty");
    this.loadingState = root.querySelector(".state.loading");
    this.errorState = root.querySelector(".state.error");
  };

  Viewer.prototype.bindEvents = function () {
    var self = this;

    this.root.addEventListener("click", function (event) {
      var dot = event.target.closest(".dot.close");
      if (dot) {
        self.close();
        return;
      }
      if (event.target === self.root) {
        // 点击窗口外的遮罩层关闭
        self.close();
        return;
      }
      var button = event.target.closest("[data-act]");
      if (!button) return;
      self.command(button.getAttribute("data-act"));
    });

    // 滚轮：⌘ / Ctrl / ⌥ + 滚轮缩放（触控板捏合会以 ctrl+wheel 形式进来），
    // 放大后用滚轮平移，和原生 scrollWheel 一致。
    this.canvas.addEventListener(
      "wheel",
      function (event) {
        if (!self.hasImage()) return;
        if (event.ctrlKey || event.metaKey || event.altKey) {
          event.preventDefault();
          var factor = Math.exp(-event.deltaY * 0.01);
          self.setZoom(self.zoom * factor, self.pointerAnchor(event), false);
          return;
        }
        if (self.zoom <= 1.001) return;
        event.preventDefault();
        self.offset.x -= event.deltaX;
        self.offset.y -= event.deltaY;
        self.clampOffset();
        self.apply();
      },
      { passive: false }
    );

    // 指针：拖动平移、适应窗口时左右拖拽翻页、双击 2× / 还原、双指捏合。
    var pointers = new Map();
    var pinchStart = null;

    this.canvas.addEventListener("pointerdown", function (event) {
      if (!self.hasImage()) return;
      if (event.button !== 0) return;
      pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
      self.canvas.setPointerCapture(event.pointerId);

      if (pointers.size === 2) {
        var values = Array.from(pointers.values());
        pinchStart = {
          distance: Math.hypot(values[0].x - values[1].x, values[0].y - values[1].y),
          zoom: self.zoom,
        };
        self.drag = null;
        return;
      }

      self.drag = {
        pointerId: event.pointerId,
        startX: event.clientX,
        startY: event.clientY,
        offsetX: self.offset.x,
        offsetY: self.offset.y,
        moved: false,
      };
      self.photo.classList.remove("anim");
      self.canvas.classList.add("dragging");
    });

    this.canvas.addEventListener("pointermove", function (event) {
      if (!pointers.has(event.pointerId)) return;
      pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });

      if (pointers.size === 2 && pinchStart) {
        var values = Array.from(pointers.values());
        var distance = Math.hypot(values[0].x - values[1].x, values[0].y - values[1].y);
        if (pinchStart.distance > 0) {
          var mid = self.pointerAnchor({
            clientX: (values[0].x + values[1].x) / 2,
            clientY: (values[0].y + values[1].y) / 2,
          });
          self.setZoom((pinchStart.zoom * distance) / pinchStart.distance, mid, false);
        }
        return;
      }

      if (!self.drag || self.drag.pointerId !== event.pointerId) return;
      var dx = event.clientX - self.drag.startX;
      var dy = event.clientY - self.drag.startY;
      if (Math.abs(dx) > 2 || Math.abs(dy) > 2) self.drag.moved = true;

      if (self.zoom > 1.001) {
        self.offset.x = self.drag.offsetX + dx;
        self.offset.y = self.drag.offsetY + dy;
        self.clampOffset();
      } else {
        // 适应窗口时轻微跟手，松手回弹；横向拖过阈值就翻页。
        self.offset.x = dx * RUBBER_BAND;
        self.offset.y = 0;
      }
      self.apply();
    });

    function endPointer(event) {
      pointers.delete(event.pointerId);
      if (pointers.size < 2) pinchStart = null;
      var drag = self.drag;
      if (!drag || drag.pointerId !== event.pointerId) return;
      self.drag = null;
      self.canvas.classList.remove("dragging");
      if (self.zoom > 1.001) {
        self.clampOffset();
        self.apply();
        return;
      }
      var dx = event.clientX - drag.startX;
      var dy = event.clientY - drag.startY;
      self.offset = { x: 0, y: 0 };
      self.photo.classList.add("anim");
      self.apply();
      if (Math.abs(dx) > SWIPE_THRESHOLD && Math.abs(dx) > Math.abs(dy)) {
        if (dx < 0) self.next();
        else self.previous();
      }
    }

    this.canvas.addEventListener("pointerup", endPointer);
    this.canvas.addEventListener("pointercancel", endPointer);

    this.canvas.addEventListener("dblclick", function (event) {
      if (!self.hasImage()) return;
      event.preventDefault();
      if (self.zoom > 1.01) {
        self.fit();
      } else {
        self.setZoom(2, self.pointerAnchor(event));
      }
    });

    // 拖入文件或图片链接
    this.root.addEventListener("dragover", function (event) {
      if (!hasFiles(event)) return;
      event.preventDefault();
      self.root.classList.add("dropping");
    });
    this.root.addEventListener("dragleave", function (event) {
      if (event.target === self.root) self.root.classList.remove("dropping");
    });
    this.root.addEventListener("drop", function (event) {
      if (!hasFiles(event)) return;
      event.preventDefault();
      self.root.classList.remove("dropping");
      self.handleDrop(event.dataTransfer);
    });

    this.onKeyDown = function (event) {
      self.handleKey(event);
    };
    document.addEventListener("keydown", this.onKeyDown, true);

    this.onResize = function () {
      self.layout();
    };
    global.addEventListener("resize", this.onResize);
  };

  function hasFiles(event) {
    var types = event.dataTransfer && event.dataTransfer.types;
    if (!types) return false;
    return (
      Array.prototype.indexOf.call(types, "Files") >= 0 ||
      Array.prototype.indexOf.call(types, "text/uri-list") >= 0
    );
  }

  /* ---------------------------- 状态与渲染 ---------------------------- */

  Viewer.prototype.hasImage = function () {
    return !!this.current() && !this.error;
  };

  Viewer.prototype.current = function () {
    return this.items[this.index] || null;
  };

  Viewer.prototype.refresh = function () {
    var count = this.items.length;
    var hasItems = count > 0;
    this.title.textContent = hasItems
      ? "图片预览 " + (this.index + 1) + "/" + count
      : "图片预览";
    this.counter.textContent = hasItems ? this.index + 1 + " / " + count : "";
    this.percent.textContent = Math.round(this.zoom * 100) + "%";

    this.buttons.prev.disabled = !hasItems || this.index <= 0;
    this.buttons.next.disabled = !hasItems || this.index + 1 >= count;
    [
      "rotate-left",
      "rotate-right",
      "flip",
      "zoom-in",
      "zoom-out",
      "fit",
      "open",
      "save",
    ].forEach(
      function (name) {
        this.buttons[name].disabled = !hasItems;
      }.bind(this)
    );

    this.emptyState.classList.toggle("visible", !hasItems);
    this.loadingState.classList.toggle("visible", hasItems && this.loading);
    this.errorState.classList.toggle("visible", hasItems && this.error && !this.loading);
    this.photo.classList.toggle("hidden", !hasItems || this.loading || this.error);
  };

  Viewer.prototype.layout = function () {
    var rect = this.canvas.getBoundingClientRect();
    this.canvasSize = { width: Math.max(rect.width, 40), height: Math.max(rect.height, 40) };
    if (!this.natural.width || !this.natural.height) return;
    var availableWidth = Math.max(this.canvasSize.width - CONTENT_INSET * 2, 40);
    var availableHeight = Math.max(this.canvasSize.height - CONTENT_INSET * 2, 40);
    var base = this.baseSize();
    this.fitScale = Math.min(availableWidth / base.width, availableHeight / base.height);
    this.clampOffset();
    this.apply();
    this.refresh();
  };

  // 旋转 90°/270° 时，用来计算适配尺寸的宽高要对调
  Viewer.prototype.baseSize = function () {
    var width = this.natural.width;
    var height = this.natural.height;
    if (Math.abs(this.rotation) % 2 === 1) {
      return { width: height, height: width };
    }
    return { width: width, height: height };
  };

  Viewer.prototype.displayedSize = function () {
    var base = this.baseSize();
    var scale = this.fitScale * this.zoom;
    return { width: base.width * scale, height: base.height * scale };
  };

  Viewer.prototype.clampOffset = function () {
    var displayed = this.displayedSize();
    var canvas = this.canvasSize || { width: 0, height: 0 };
    var marginX = Math.max((displayed.width - canvas.width) / 2 + CONTENT_INSET, 0);
    var marginY = Math.max((displayed.height - canvas.height) / 2 + CONTENT_INSET, 0);
    if (displayed.width <= canvas.width) this.offset.x = 0;
    else this.offset.x = clamp(this.offset.x, -marginX, marginX);
    if (displayed.height <= canvas.height) this.offset.y = 0;
    else this.offset.y = clamp(this.offset.y, -marginY, marginY);
  };

  Viewer.prototype.apply = function () {
    if (!this.natural.width) return;
    var scale = this.fitScale * this.zoom;
    this.photo.style.width = this.natural.width + "px";
    this.photo.style.height = this.natural.height + "px";
    this.photo.style.transform =
      "translate(-50%, -50%) translate(" +
      this.offset.x +
      "px, " +
      this.offset.y +
      "px) rotate(" +
      this.rotation * 90 +
      "deg) scale(" +
      scale +
      ") scaleX(" +
      (this.flipped ? -1 : 1) +
      ")";
  };

  /* ------------------------------ 加载 ------------------------------ */

  Viewer.prototype.loadCurrent = function (reset) {
    var self = this;
    if (!this.items.length) {
      this.natural = { width: 0, height: 0 };
      this.refresh();
      return;
    }
    var item = this.current();
    var token = ++this.loadToken;
    this.loading = true;
    this.error = false;
    this.refresh();

    var probe = new Image();
    probe.decoding = "async";
    probe.onload = function () {
      if (token !== self.loadToken) return;
      self.natural = { width: probe.naturalWidth, height: probe.naturalHeight };
      self.photo.src = item.url;
      self.photo.alt = item.name || "";
      self.loading = false;
      self.error = false;
      if (reset) {
        self.rotation = 0;
        self.flipped = false;
        self.zoom = 1;
        self.offset = { x: 0, y: 0 };
      }
      self.layout();
      self.refresh();
      self.prefetch();
    };
    probe.onerror = function () {
      if (token !== self.loadToken) return;
      self.loading = false;
      self.error = true;
      self.refresh();
      self.prefetch();
    };
    probe.src = item.url;
  };

  Viewer.prototype.prefetch = function () {
    [-1, 1].forEach(
      function (step) {
        var item = this.items[this.index + step];
        if (!item) return;
        var image = new Image();
        image.decoding = "async";
        image.src = item.url;
      }.bind(this)
    );
  };

  /* ------------------------------ 命令 ------------------------------ */

  Viewer.prototype.command = function (name) {
    switch (name) {
      case "prev":
        return this.previous();
      case "next":
        return this.next();
      case "rotate-left":
        return this.rotate(-1);
      case "rotate-right":
        return this.rotate(1);
      case "flip":
        return this.flip();
      case "zoom-in":
        return this.setZoom(this.zoom * 1.25);
      case "zoom-out":
        return this.setZoom(this.zoom / 1.25);
      case "fit":
        return this.fit();
      case "open":
        return this.openOriginal();
      case "save":
        return this.save();
      case "retry":
        return this.loadCurrent(false);
      default:
        return undefined;
    }
  };

  Viewer.prototype.go = function (index) {
    if (!this.items.length) return;
    var next = clamp(index, 0, this.items.length - 1);
    if (next === this.index) return;
    this.index = next;
    this.loadCurrent(true);
    this.refresh();
  };

  Viewer.prototype.previous = function () {
    this.go(this.index - 1);
  };

  Viewer.prototype.next = function () {
    this.go(this.index + 1);
  };

  Viewer.prototype.pointerAnchor = function (event) {
    var rect = this.canvas.getBoundingClientRect();
    return {
      x: event.clientX - rect.left - rect.width / 2,
      y: event.clientY - rect.top - rect.height / 2,
    };
  };

  // 缩放时让锚点（鼠标位置）下的画面保持不动，公式同原生 setZoom
  Viewer.prototype.setZoom = function (nextZoom, anchor, animate) {
    if (!this.natural.width) return;
    var clamped = clamp(nextZoom, MIN_ZOOM, MAX_ZOOM);
    if (Math.abs(clamped - this.zoom) < 0.0005) return;
    var point = anchor || { x: 0, y: 0 };
    var ratio = clamped / this.zoom;
    this.offset.x = point.x + (this.offset.x - point.x) * ratio;
    this.offset.y = point.y + (this.offset.y - point.y) * ratio;
    this.zoom = clamped;
    this.clampOffset();
    if (animate === false) this.photo.classList.remove("anim");
    else this.photo.classList.add("anim");
    this.apply();
    this.refresh();
  };

  Viewer.prototype.fit = function () {
    if (!this.natural.width) return;
    this.zoom = 1;
    this.offset = { x: 0, y: 0 };
    this.photo.classList.add("anim");
    this.clampOffset();
    this.apply();
    this.refresh();
  };

  Viewer.prototype.rotate = function (quarterTurns) {
    if (!this.natural.width) return;
    this.rotation = (((this.rotation + quarterTurns) % 4) + 4) % 4;
    this.offset = { x: 0, y: 0 };
    this.photo.classList.add("anim");
    this.layout();
  };

  Viewer.prototype.flip = function () {
    if (!this.natural.width) return;
    this.flipped = !this.flipped;
    this.photo.classList.add("anim");
    this.apply();
  };

  /* ------------------------- 浏览器打开 / 存储 ------------------------- */

  Viewer.prototype.openOriginal = function () {
    var item = this.current();
    if (!item) return;
    global.open(item.url, "_blank", "noopener");
  };

  Viewer.prototype.save = function () {
    var item = this.current();
    if (!item) return;
    var name = item.name || fileNameFromURL(item.url);
    fetch(item.url)
      .then(function (response) {
        if (!response.ok) throw new Error("HTTP " + response.status);
        return response.blob();
      })
      .then(function (blob) {
        var href = URL.createObjectURL(blob);
        var link = document.createElement("a");
        link.href = href;
        link.download = name;
        link.rel = "noopener";
        document.body.appendChild(link);
        link.click();
        link.remove();
        setTimeout(function () {
          URL.revokeObjectURL(href);
        }, 4000);
      })
      .catch(function () {
        // 跨域且没有 CORS 头时不能读字节，退回「在新标签页打开」，
        // 由浏览器自己的下载/另存为处理。
        global.open(item.url, "_blank", "noopener");
      });
  };

  /* --------------------------- 拖拽 / 键盘 --------------------------- */

  Viewer.prototype.handleDrop = function (transfer) {
    var added = [];
    if (transfer.files && transfer.files.length) {
      Array.prototype.forEach.call(transfer.files, function (file) {
        if (!/^image\//.test(file.type) && !/\.(png|jpe?g|gif|webp|avif|bmp|heic|svg)$/i.test(file.name)) {
          return;
        }
        added.push({ url: URL.createObjectURL(file), name: file.name });
      });
    } else {
      var text = transfer.getData("text/uri-list") || transfer.getData("text/plain") || "";
      text.split(/\r?\n/).forEach(function (line) {
        var url = line.trim();
        if (!url || url.charAt(0) === "#") return;
        added.push({ url: url, name: fileNameFromURL(url) });
      });
    }
    if (!added.length) return;

    if (!this.items.length) this.items = added;
    else this.items = this.items.concat(added);
    this.index = this.items.length - added.length;
    this.loadCurrent(true);
    this.refresh();
  };

  Viewer.prototype.handleKey = function (event) {
    if (event.defaultPrevented) return;
    var target = event.target;
    if (
      target &&
      (target.isContentEditable ||
        /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName || ""))
    ) {
      return;
    }
    var key = event.key;
    var meta = event.metaKey || event.ctrlKey;
    if (key === "Escape") {
      event.preventDefault();
      this.close();
      return;
    }
    if (meta && (key === "s" || key === "S")) {
      event.preventDefault();
      this.save();
      return;
    }
    if (meta) return;
    if (key === "ArrowLeft") {
      event.preventDefault();
      this.previous();
    } else if (key === "ArrowRight") {
      event.preventDefault();
      this.next();
    } else if (key === "+" || key === "=") {
      event.preventDefault();
      this.setZoom(this.zoom * 1.25);
    } else if (key === "-" || key === "_") {
      event.preventDefault();
      this.setZoom(this.zoom / 1.25);
    } else if (key === "0") {
      event.preventDefault();
      this.fit();
    } else if (key === "r") {
      event.preventDefault();
      this.rotate(1);
    } else if (key === "R") {
      event.preventDefault();
      this.rotate(-1);
    } else if (key === "f" || key === "F") {
      event.preventDefault();
      this.flip();
    }
  };

  /* ------------------------------ 生命周期 ------------------------------ */

  Viewer.prototype.close = function () {
    if (this.closed) return;
    this.closed = true;
    document.removeEventListener("keydown", this.onKeyDown, true);
    global.removeEventListener("resize", this.onResize);
    if (this.host && this.host.parentNode) this.host.parentNode.removeChild(this.host);
    document.documentElement.style.overflow = this.previousOverflow || "";
    document.documentElement.style.paddingRight = this.previousPadding || "";
    if (typeof this.options.onClose === "function") this.options.onClose();
    if (active === this) active = null;
  };

  /* ------------------------------------------------------------------ *
   * 对外 API
   * ------------------------------------------------------------------ */

  var active = null;

  function open(list, index, options) {
    var items = normalizeItems(list);
    close();
    var lockedOverflow = document.documentElement.style.overflow;
    var lockedPadding = document.documentElement.style.paddingRight;
    var viewer = new Viewer(items, index || 0, options);
    viewer.previousOverflow = lockedOverflow;
    viewer.previousPadding = lockedPadding;
    document.documentElement.style.overflow = "hidden";
    active = viewer;
    return {
      close: function () {
        viewer.close();
      },
      next: function () {
        viewer.next();
      },
      previous: function () {
        viewer.previous();
      },
      viewer: viewer,
    };
  }

  function close() {
    if (active) active.close();
  }

  // 把 root 里的图片绑定成「点一下就能预览」，同一个 [data-seeimage-gallery]
  // 容器内的图片自动成为一组。
  function bind(root, selector) {
    var host = root || document.body;
    var pattern = selector || "[data-seeimage], img";
    if (host.__seeimageBound) return;
    host.__seeimageBound = true;
    host.addEventListener("click", function (event) {
      var target = event.target.closest(pattern);
      if (!target || !host.contains(target)) return;
      var scope = target.closest("[data-seeimage-gallery]") || host;
      var nodes = Array.prototype.slice.call(scope.querySelectorAll(pattern));
      var urls = nodes.map(urlOfNode).filter(Boolean);
      if (!urls.length) return;
      var index = Math.max(nodes.indexOf(target), 0);
      if (index >= urls.length) index = urls.length - 1;
      if (target.isContentEditable) return;
      // 让 <a href="大图"> 的默认跳转失效
      if (target.tagName === "A") event.preventDefault();
      open(urls, index);
    });
  }

  function collect(scope, selector) {
    var host = scope || document;
    var pattern = selector || "[data-seeimage], img";
    return Array.prototype.slice.call(host.querySelectorAll(pattern)).map(urlOfNode).filter(Boolean);
  }

  var SeeImage = {
    version: "1.0.0",
    open: open,
    close: close,
    bind: bind,
    collect: collect,
  };

  global.SeeImage = SeeImage;
  global.__seeimagePreviewSingle = function (url) {
    return open([url], 0);
  };
})(window);
