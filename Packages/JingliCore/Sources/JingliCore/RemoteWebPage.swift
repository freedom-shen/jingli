import Foundation

/// 手机网页端的单页应用（内联 HTML/CSS/JS，无外部依赖、无 CDN）。
enum RemoteWebPage {
    static let html = #"""
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#08080a">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="精力管理">
<meta name="format-detection" content="telephone=no">
<title>精力管理</title>
<style>
  :root {
    --bg: #08080a;
    --card: #141416;
    --card-2: #1b1b1e;
    --text: #f5f5f6;
    --secondary: #8b8b92;
    --accent: #8fa8e8;
    --sage: #8fb894;
    --tomato: #c75c40;
    --line: rgba(255, 255, 255, 0.08);
  }
  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  html, body { margin: 0; padding: 0; background: var(--bg); color: var(--text); }
  body {
    font-family: -apple-system, "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif;
    font-size: 15px;
    line-height: 1.4;
    min-height: 100vh;
    padding: env(safe-area-inset-top) 0 calc(96px + env(safe-area-inset-bottom));
  }
  header {
    padding: 22px 20px 12px;
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    gap: 12px;
  }
  .day { font-size: 22px; font-weight: 650; letter-spacing: 0.2px; }
  .weekday { font-size: 12px; color: var(--secondary); margin-top: 2px; }
  .stats { display: flex; gap: 14px; font-size: 13px; color: var(--secondary); }
  .stats b { color: var(--text); font-weight: 600; font-variant-numeric: tabular-nums; }
  .banner {
    margin: 4px 20px 10px;
    padding: 10px 12px;
    border-radius: 12px;
    background: var(--card);
    border: 1px solid var(--line);
    color: var(--secondary);
    font-size: 12px;
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .banner button {
    margin-left: auto;
    flex: none;
    border: 0;
    border-radius: 8px;
    background: var(--sage);
    color: #0d1a11;
    font-size: 12px;
    font-weight: 650;
    padding: 6px 10px;
  }
  main { padding: 4px 14px; }
  .empty {
    margin: 40px 22px;
    color: var(--secondary);
    font-size: 13px;
    text-align: center;
    line-height: 1.8;
  }
  .task {
    width: 100%;
    display: flex;
    align-items: flex-start;
    gap: 12px;
    text-align: left;
    border: 1px solid var(--line);
    background: var(--card);
    color: var(--text);
    border-radius: 14px;
    padding: 13px 14px;
    margin: 8px 0;
    font: inherit;
    transition: background 0.15s ease, transform 0.1s ease;
  }
  .task:active { transform: scale(0.995); background: var(--card-2); }
  .check {
    flex: none;
    width: 21px;
    height: 21px;
    margin-top: 1px;
    border-radius: 50%;
    border: 1.5px solid rgba(255, 255, 255, 0.28);
    display: grid;
    place-items: center;
    transition: all 0.15s ease;
  }
  .check svg { width: 11px; height: 11px; opacity: 0; }
  .task.done .check { background: var(--sage); border-color: var(--sage); }
  .task.done .check svg { opacity: 1; }
  .task.done .title { color: var(--secondary); text-decoration: line-through; }
  .body { flex: 1; min-width: 0; }
  .title { display: block; font-size: 15px; font-weight: 550; overflow-wrap: anywhere; }
  .meta { display: block; margin-top: 3px; font-size: 11.5px; color: var(--secondary); overflow-wrap: anywhere; }
  .chip {
    display: inline-block;
    padding: 1px 7px;
    margin-right: 6px;
    border-radius: 999px;
    background: rgba(143, 184, 148, 0.14);
    color: var(--sage);
    font-size: 11px;
  }
  .lane {
    display: inline-block;
    padding: 1px 7px;
    margin-right: 6px;
    border-radius: 999px;
    background: rgba(143, 168, 232, 0.13);
    color: var(--accent);
    font-size: 11px;
  }
  #addbar {
    position: fixed;
    left: 0; right: 0; bottom: 0;
    padding: 10px 14px calc(10px + env(safe-area-inset-bottom));
    background: rgba(8, 8, 10, 0.86);
    -webkit-backdrop-filter: blur(14px);
    backdrop-filter: blur(14px);
    border-top: 1px solid var(--line);
    display: flex;
    gap: 8px;
  }
  #title {
    flex: 1;
    min-width: 0;
    border: 1px solid var(--line);
    background: var(--card);
    color: var(--text);
    border-radius: 12px;
    padding: 12px 14px;
    font: inherit;
    font-size: 16px; /* 避免 iOS 聚焦放大 */
    outline: none;
  }
  #title::placeholder { color: rgba(139, 139, 146, 0.8); }
  #title:focus { border-color: rgba(143, 184, 148, 0.55); }
  #add {
    flex: none;
    border: 0;
    border-radius: 12px;
    background: var(--sage);
    color: #0d1a11;
    font: inherit;
    font-weight: 700;
    padding: 12px 18px;
  }
  #add:disabled { opacity: 0.5; }
  .pairing { padding: 60px 28px; text-align: center; color: var(--secondary); font-size: 13px; line-height: 1.9; }
  .pairing h1 { font-size: 18px; color: var(--text); margin-bottom: 10px; }
  #toast {
    position: fixed;
    left: 50%;
    bottom: calc(92px + env(safe-area-inset-bottom));
    transform: translateX(-50%) translateY(8px);
    max-width: 86vw;
    padding: 9px 14px;
    border-radius: 10px;
    background: rgba(199, 92, 64, 0.95);
    color: #fff;
    font-size: 12.5px;
    opacity: 0;
    pointer-events: none;
    transition: opacity 0.2s ease, transform 0.2s ease;
  }
  #toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }
  #toast.ok { background: rgba(143, 184, 148, 0.95); color: #0d1a11; }
</style>
</head>
<body>
<header>
  <div>
    <div class="day" id="day">今天</div>
    <div class="weekday" id="weekday"></div>
  </div>
  <div class="stats">
    <span>🍅 <b id="pomodoros">0</b></span>
    <span>✓ <b id="completed">0</b></span>
  </div>
</header>
<div class="banner" id="banner" hidden>
  <span id="banner-text">今天还没开始</span>
  <button id="start-day">开启今天</button>
</div>
<main id="list"></main>
<div class="empty" id="empty" hidden>今天还没有任务<br>在下面输入一件要今天做的事</div>
<div class="pairing" id="pairing" hidden>
  <h1>还没配对</h1>
  请用「精力管理 → 设置 → 手机网页」里复制的链接打开。<br>
  链接里带一次性配对 token，打开一次后这台手机会记住。
</div>
<div id="toast"></div>
<form id="addbar" autocomplete="off">
  <input id="title" type="text" placeholder="加一件今天要做的事" maxlength="120" enterkeyhint="done">
  <button id="add" type="submit">加入</button>
</form>
<script>
(function () {
  var token = "";
  var state = null;
  var busy = false;

  try {
    var params = new URLSearchParams(location.search);
    var fromURL = params.get("t") || params.get("token");
    if (fromURL) {
      token = fromURL;
      try { localStorage.setItem("jingli.token", fromURL); } catch (e) {}
      history.replaceState(null, "", location.pathname);
    } else {
      token = localStorage.getItem("jingli.token") || "";
    }
  } catch (e) {}

  function toast(message, ok) {
    var el = document.getElementById("toast");
    el.textContent = message;
    el.className = ok ? "show ok" : "show";
    clearTimeout(toast._timer);
    toast._timer = setTimeout(function () { el.className = ""; }, 2600);
  }

  function showPairing() {
    var pairing = document.getElementById("pairing");
    pairing.hidden = false;
    document.getElementById("list").hidden = true;
    document.getElementById("addbar").hidden = true;
  }

  function api(path, options) {
    var opts = options || {};
    opts.credentials = "same-origin";
    opts.headers = opts.headers || {};
    if (token) opts.headers["X-Jingli-Token"] = token;
    return fetch(path, opts).then(function (response) {
      if (response.status === 401) {
        showPairing();
        throw new Error("未配对");
      }
      return response.json().then(function (json) {
        if (!response.ok || !json.ok) {
          throw new Error(json.error || ("请求失败 " + response.status));
        }
        return json;
      });
    });
  }

  function weekdayText(date) {
    var names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];
    return names[date.getDay()];
  }

  function render(data) {
    state = data;
    var today = data.today || {};
    var tasks = today.tasks || [];
    var projects = {};
    (today.projects || []).forEach(function (project) { projects[project.id] = project.name; });

    var date = new Date(data.date + "T00:00:00");
    document.getElementById("day").textContent = (date.getMonth() + 1) + "月" + date.getDate() + "日";
    document.getElementById("weekday").textContent = weekdayText(date);
    var stats = data.stats || {};
    document.getElementById("pomodoros").textContent = stats.pomodoros || 0;
    document.getElementById("completed").textContent = stats.completedTasks || 0;

    var list = document.getElementById("list");
    list.innerHTML = "";
    var doneCount = 0;
    tasks.forEach(function (task) {
      if (task.done) doneCount += 1;
      var row = document.createElement("button");
      row.type = "button";
      row.className = "task" + (task.done ? " done" : "");
      row.setAttribute("aria-label", (task.done ? "取消完成：" : "完成：") + task.title);
      row.addEventListener("click", function () { toggle(task); });

      var check = document.createElement("span");
      check.className = "check";
      check.innerHTML = '<svg viewBox="0 0 12 12" fill="none"><path d="M2 6.2 4.8 9 10 3.4" stroke="#0d1a11" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
      row.appendChild(check);

      var body = document.createElement("span");
      body.className = "body";
      var title = document.createElement("span");
      title.className = "title";
      title.textContent = task.title;
      body.appendChild(title);

      var meta = document.createElement("span");
      meta.className = "meta";
      if (task.lane === "main") {
        var lane = document.createElement("span");
        lane.className = "lane";
        lane.textContent = "主线";
        meta.appendChild(lane);
      }
      if (task.projectId && projects[task.projectId]) {
        var chip = document.createElement("span");
        chip.className = "chip";
        chip.textContent = projects[task.projectId];
        meta.appendChild(chip);
      }
      if (task.note) {
        meta.appendChild(document.createTextNode(task.note));
      }
      if (meta.childNodes.length) body.appendChild(meta);
      row.appendChild(body);
      list.appendChild(row);
    });
    document.getElementById("empty").hidden = tasks.length > 0;

    var banner = document.getElementById("banner");
    if (!today.dayStarted && tasks.some(function (task) { return !task.done; })) {
      banner.hidden = false;
      document.getElementById("banner-text").textContent = "今天还没开始 · 已排 " + tasks.length + " 件";
    } else {
      banner.hidden = true;
    }
    document.getElementById("completed").textContent = doneCount;
  }

  function load() {
    return api("/api/today").then(render).catch(function (error) {
      if (error.message !== "未配对") toast(error.message);
    });
  }

  function toggle(task) {
    if (busy) return;
    busy = true;
    api("/api/tasks/" + encodeURIComponent(task.id) + "/toggle", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ done: !task.done })
    }).then(function () {
      return load();
    }).catch(function (error) {
      toast(error.message);
    }).finally(function () { busy = false; });
  }

  function addTask(event) {
    event.preventDefault();
    var input = document.getElementById("title");
    var title = input.value.trim();
    if (!title || busy) return;
    busy = true;
    document.getElementById("add").disabled = true;
    api("/api/tasks", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title: title })
    }).then(function () {
      input.value = "";
      toast("已加入今天", true);
      return load();
    }).catch(function (error) {
      toast(error.message);
    }).finally(function () {
      busy = false;
      document.getElementById("add").disabled = false;
    });
  }

  function startDay() {
    if (busy) return;
    busy = true;
    api("/api/day/start", { method: "POST" }).then(function () {
      toast("今天开始了", true);
      return load();
    }).catch(function (error) {
      toast(error.message);
    }).finally(function () { busy = false; });
  }

  document.getElementById("addbar").addEventListener("submit", addTask);
  document.getElementById("start-day").addEventListener("click", startDay);
  document.addEventListener("visibilitychange", function () {
    if (!document.hidden) load();
  });
  setInterval(function () {
    if (!document.hidden) load();
  }, 20000);
  load();
})();
</script>
</body>
</html>
"""#
}
