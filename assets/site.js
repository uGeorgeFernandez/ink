// INK website helpers: syntax highlighting, nav, example tabs, docs scrollspy.
(function () {
  var KEYWORDS = ["let", "const", "fn", "return", "if", "else", "for", "in", "while", "loop", "break", "continue", "show", "true", "false"];
  var TYPES = ["num", "int", "text", "list"];
  var BUILTINS = ["len", "sum", "min", "max", "abs", "input", "input_text", "write_file", "read_file"];

  function esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  function highlight(src) {
    var re = /(\/\/[^\n]*)|("(?:[^"\\]|\\.)*")|(\b\d+\b)|(->|\.\.|==|!=|>=|<=)|([A-Za-z_][A-Za-z0-9_]*)|([\s\S])/g;
    var out = "", m;
    while ((m = re.exec(src))) {
      if (m[1]) out += '<span class="t-co">' + esc(m[1]) + "</span>";
      else if (m[2]) out += '<span class="t-st">' + esc(m[2]) + "</span>";
      else if (m[3]) out += '<span class="t-nu">' + m[3] + "</span>";
      else if (m[4]) out += '<span class="t-op">' + esc(m[4]) + "</span>";
      else if (m[5]) {
        var w = m[5];
        if (KEYWORDS.indexOf(w) >= 0) out += '<span class="t-kw">' + w + "</span>";
        else if (TYPES.indexOf(w) >= 0) out += '<span class="t-ty">' + w + "</span>";
        else if (BUILTINS.indexOf(w) >= 0 || /^\s*\(/.test(src.slice(re.lastIndex))) out += '<span class="t-fn">' + w + "</span>";
        else out += w;
      } else out += esc(m[6]);
    }
    return out;
  }

  document.querySelectorAll("code.ink").forEach(function (el) {
    el.innerHTML = highlight(el.textContent.replace(/^\n/, ""));
  });

  // Mobile nav
  var toggle = document.querySelector(".nav-toggle");
  var links = document.querySelector(".nav-links");
  if (toggle && links) {
    toggle.addEventListener("click", function () {
      var open = links.classList.toggle("open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    links.querySelectorAll("a").forEach(function (a) {
      a.addEventListener("click", function () { links.classList.remove("open"); });
    });
  }

  // Example tabs
  var tabs = document.querySelectorAll(".ex-tab");
  tabs.forEach(function (tab) {
    tab.addEventListener("click", function () {
      tabs.forEach(function (t) { t.classList.toggle("active", t === tab); t.setAttribute("aria-selected", t === tab); });
      document.querySelectorAll(".ex-panel").forEach(function (p) {
        p.classList.toggle("active", p.id === tab.dataset.target);
      });
    });
  });

  // Docs scrollspy
  var tocLinks = document.querySelectorAll(".toc a");
  if (tocLinks.length && "IntersectionObserver" in window) {
    var byId = {};
    tocLinks.forEach(function (a) { byId[a.getAttribute("href").slice(1)] = a; });
    var obs = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting && byId[e.target.id]) {
          tocLinks.forEach(function (a) { a.classList.remove("active"); });
          byId[e.target.id].classList.add("active");
        }
      });
    }, { rootMargin: "-80px 0px -70% 0px" });
    Object.keys(byId).forEach(function (id) {
      var sec = document.getElementById(id);
      if (sec) obs.observe(sec);
    });
  }
  var sel = document.querySelector(".mobile-toc select:not(#codeJump)");
  if (sel) sel.addEventListener("change", function () { location.hash = sel.value; });

  var yr = document.getElementById("year");
  if (yr) yr.textContent = new Date().getFullYear();
})();

// Feedback form — composes an email to the INK team (no backend needed).
(function () {
  var ff = document.getElementById("feedbackForm");
  if (!ff) return;
  ff.addEventListener("submit", function (e) {
    e.preventDefault();
    var d = new FormData(ff);
    var note = document.getElementById("ffNote");
    var msg = (d.get("message") || "").toString().trim();
    if (!msg) { note.textContent = "Please write a little feedback first."; note.className = "ff-note err"; return; }
    var body = "Feedback on INK\n\n" +
      "Name: " + (d.get("name") || "-") + "\n" +
      "Email: " + (d.get("email") || "-") + "\n" +
      "How easy: " + (d.get("rating") || "-") + "\n\n" +
      msg + "\n";
    var link = "mailto:inddn1947@gmail.com?subject=" + encodeURIComponent("INK feedback") +
               "&body=" + encodeURIComponent(body);
    window.location.href = link;
    note.textContent = "Thank you! Your email app should open — just press send.";
    note.className = "ff-note ok";
    ff.reset();
  });
})();
