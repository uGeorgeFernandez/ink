// Side-by-side code comparison.
// compare.html: one task at a time, chosen with tabs (#taskTabs).
// code.html: every task listed by category (#allTasks).
// Code samples live in assets/snippets.html.
(function () {
  var LANGS = [
    { id: "ink", name: "INK", cls: "c-ink" },
    { id: "py", name: "Python", cls: "c-py" },
    { id: "php", name: "PHP", cls: "c-php" },
    { id: "cs", name: "C# (.NET)", cls: "c-cs" },
    { id: "node", name: "Node.js", cls: "c-node" }
  ];

  var CATEGORIES = [
    { id: "basics", name: "Basics" },
    { id: "flow", name: "Decisions & loops" },
    { id: "fns", name: "Functions" },
    { id: "data", name: "Lists & maps" },
    { id: "io", name: "Input & files" },
    { id: "safety", name: "Safety" }
  ];

  var TASKS = [
    { id: "hello", cat: "basics", label: "Hello", title: "Print a message", desc: "The first program everyone writes.", out: "Namaste, India!" },
    { id: "vars", cat: "basics", label: "Variables", title: "Store and show values", desc: "Keep a name and an age, then show them.", out: "Name: Priya\nAge: 21" },
    { id: "const", cat: "basics", title: "A value that never changes", desc: "Create a constant and show it.", out: "100" },
    { id: "maths", cat: "basics", title: "Maths: 10 and 3", desc: "Add, subtract, multiply and divide. Watch the last line: dividing works differently in each language.", out: null },
    { id: "join", cat: "basics", title: "Join text and a number", desc: "Put a number inside a sentence.", out: "Age: 30" },
    { id: "if", cat: "flow", label: "If / else", title: "Make a decision", desc: "Give a grade based on marks.", out: "Grade B" },
    { id: "loop", cat: "flow", label: "Loops", title: "Count from 0 to 4", desc: "Repeat something five times.", out: "0\n1\n2\n3\n4" },
    { id: "while", cat: "flow", title: "Repeat while something is true", desc: "A while loop that counts to 2.", out: "0\n1\n2" },
    { id: "break", cat: "flow", title: "Stop a loop early", desc: "Count up, but stop once we pass 4.", out: "0\n1\n2\n3\n4" },
    { id: "fn", cat: "fns", label: "Functions", title: "A reusable function", desc: "Write a function that adds two numbers.", out: "8" },
    { id: "greet", cat: "fns", title: "A function that returns text", desc: "Build a greeting from a name.", out: "Namaste George" },
    { id: "fact", cat: "fns", title: "Recursion: factorial of 5", desc: "A function that calls itself: 5 × 4 × 3 × 2 × 1.", out: "120" },
    { id: "list", cat: "data", label: "Lists", title: "Work with a list", desc: "Count, add up and read items in a list.", out: "4\n100\n10" },
    { id: "listset", cat: "data", title: "Change an item in a list", desc: "Replace the first item.", out: "100" },
    { id: "each", cat: "data", title: "Go through every item", desc: "Show each city in a list.", out: "Delhi\nMumbai\nHyderabad" },
    { id: "map", cat: "data", label: "Maps", title: "Look up by name", desc: "Store each person's city and look it up.", out: "Hyderabad\nPriya lives in Delhi" },
    { id: "biggest", cat: "data", title: "Find the biggest number", desc: "A small real program: a function, a list and a loop.", out: "15" },
    { id: "input", cat: "io", label: "User input", title: "Read what the user types", desc: "Ask for a name and greet the person. Notice how much more Node.js needs.", out: "(user types Ravi)\nNamaste Ravi" },
    { id: "inputnum", cat: "io", title: "Read a number and double it", desc: "Text from the keyboard must become a number before doing maths.", out: "(user types 21)\n42" },
    { id: "file", cat: "io", label: "Files", title: "Save and read a file", desc: "Write text to a file, then read it back.", out: "Jai Hind!" },
    { id: "safe", cat: "safety", label: "Safety", title: "Reading past the end of a list", desc: "The list has 3 items; we ask for item 99. A safe language stops with a clear error. PHP and JavaScript quietly carry on, which can hide bugs.", out: null },
    { id: "types", cat: "safety", title: "Passing the wrong type", desc: "We give text to a function that expects numbers. Some languages catch this before running; others only when the line runs, or never.", out: null }
  ];

  // Tasks shown as tabs on compare.html (the short list).
  var TAB_TASKS = ["hello", "vars", "if", "loop", "fn", "list", "map", "input", "file", "safe"];

  var KW = {
    ink: "let const fn return if else for in while loop break continue show true false",
    py: "def return if elif else for in while import from as with and or not True False None class pass break continue lambda",
    php: "function return if elseif else for foreach while echo as new class true false null const break",
    cs: "var new return if else for foreach in while class static void public private true false null using const break",
    node: "const let var function return if else for while of in new true false null undefined class async await require break"
  };
  var TY = {
    ink: "num int text list",
    py: "int str float list dict",
    php: "int string float array",
    cs: "int string bool double Dictionary Console File Math",
    node: "console process fs Math Number"
  };

  function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
  function wrap(c, s) { return '<span class="' + c + '">' + esc(s) + "</span>"; }

  function highlight(src, lang) {
    var kw = KW[lang].split(" "), ty = TY[lang].split(" ");
    var comment = lang === "py" ? "#[^\\n]*" : "\\/\\/[^\\n]*";
    var re = new RegExp(
      "(" + comment + ")|(<\\?php)|(\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'|`[^`]*`)|(\\$[A-Za-z_]\\w*)|(\\b\\d+\\b)|(->|=>|\\.\\.|==|!=|>=|<=|\\+\\+)|([A-Za-z_]\\w*)|([\\s\\S])",
      "g"
    );
    var out = "", m;
    while ((m = re.exec(src))) {
      if (m[1]) out += wrap("t-co", m[1]);
      else if (m[2]) out += wrap("t-kw", m[2]);
      else if (m[3]) out += wrap("t-st", m[3]);
      else if (m[4]) out += wrap("t-va", m[4]);
      else if (m[5]) out += wrap("t-nu", m[5]);
      else if (m[6]) out += wrap("t-op", m[6]);
      else if (m[7]) {
        var w = m[7];
        if (kw.indexOf(w) >= 0) out += wrap("t-kw", w);
        else if (ty.indexOf(w) >= 0) out += wrap("t-ty", w);
        else if (/^\s*\(/.test(src.slice(re.lastIndex))) out += wrap("t-fn", w);
        else out += esc(w);
      } else out += esc(m[8]);
    }
    return out;
  }

  function lineCount(code) {
    return code.split("\n").filter(function (x) { return x.trim() !== ""; }).length;
  }

  function taskById(id) { return TASKS.filter(function (t) { return t.id === id; })[0]; }

  // Keeps the sticky offset (nav + toolbar height) current for the table box.
  function updateCtTop() {
    var nav = document.querySelector(".nav");
    var bar = document.querySelector(".code-toolbar");
    var h = (nav ? nav.offsetHeight : 66) + (bar ? bar.offsetHeight : 0) + 8;
    document.documentElement.style.setProperty("--ct-top", h + "px");
  }

  // Scroll a program into view. In card view the page scrolls; in table view
  // the frozen-header box scrolls internally, just below its header row.
  function jumpTo(id, smooth) {
    var plainId = id.replace(/^(t-|row-)/, "");
    if (state.view === "table") {
      var row = document.getElementById("row-" + plainId);
      var wrap = document.querySelector("#tableView .ct-wrap");
      if (row && wrap) {
        var ctTop = parseInt(getComputedStyle(document.documentElement).getPropertyValue("--ct-top"), 10) || 150;
        var thead = wrap.querySelector("thead");
        var theadH = thead ? thead.getBoundingClientRect().height : 0;
        // Inner scroll is relative to the box, so it is unaffected by page scroll.
        var delta = row.getBoundingClientRect().top - wrap.getBoundingClientRect().top;
        wrap.scrollTop += delta - theadH - 6;
        // Then slide the page so the box sits just under the sticky toolbar.
        var y = wrap.getBoundingClientRect().top + window.pageYOffset - ctTop;
        window.scrollTo({ top: Math.max(0, y), behavior: "instant" });
      }
    } else {
      var target = document.getElementById("t-" + plainId);
      if (target) {
        var bar = document.querySelector(".code-toolbar");
        var offset = bar ? bar.getBoundingClientRect().height + 66 + 12 : 84;
        window.scrollTo({ top: target.getBoundingClientRect().top + window.pageYOffset - offset, behavior: "instant" });
      }
    }
    setTimeout(function () {
      document.querySelectorAll("#codeToc a").forEach(function (a) {
        a.classList.toggle("active", a.getAttribute("href") === "#t-" + plainId);
      });
    }, 50);
    if (history.replaceState) history.replaceState(null, "", "#t-" + plainId);
  }

  var snips = {};
  var state = { task: "hello", view: "cards", on: { ink: true, py: true, php: true, cs: true, node: true } };
  try {
    var saved = JSON.parse(localStorage.getItem("ink-compare-langs") || "null");
    if (saved) state.on = saved;
    if (localStorage.getItem("ink-code-view") === "table") state.view = "table";
  } catch (e) {}

  var togglesEl = document.getElementById("langToggles");
  var tabsEl = document.getElementById("taskTabs");
  var allEl = document.getElementById("allTasks");
  if (!togglesEl) return;

  function cardsFor(task) {
    var frag = document.createDocumentFragment();
    LANGS.forEach(function (l) {
      if (!state.on[l.id]) return;
      var s = snips[task.id + ":" + l.id];
      if (!s) return;
      var card = document.createElement("div");
      card.className = "code-card " + l.cls;
      var n = lineCount(s.code);
      var res = s.res || task.out || "";
      card.innerHTML =
        '<header><span class="lang-dot"></span><b>' + l.name + '</b><span class="meta">' + n + (n === 1 ? " line" : " lines") + "</span></header>" +
        "<pre><code>" + highlight(s.code, l.id) + "</code></pre>" +
        (s.note ? '<div class="note">' + esc(s.note) + "</div>" : "") +
        '<div class="res' + (s.bad ? " bad" : "") + '">' + esc(res) + "</div>";
      frag.appendChild(card);
    });
    return frag;
  }

  function renderToggles() {
    togglesEl.querySelectorAll(".lang-toggle").forEach(function (b) {
      b.classList.toggle("on", !!state.on[b.dataset.lang]);
      b.setAttribute("aria-pressed", !!state.on[b.dataset.lang]);
    });
  }

  function renderTabs() {
    var task = taskById(state.task);
    tabsEl.querySelectorAll(".task-tab").forEach(function (b) {
      var on = b.dataset.task === state.task;
      b.classList.toggle("active", on);
      b.setAttribute("aria-selected", on);
    });
    document.getElementById("taskIntro").innerHTML = "<h3>" + esc(task.title) + "</h3><p>" + esc(task.desc) + "</p>";
    var grid = document.getElementById("codeGrid");
    grid.innerHTML = "";
    grid.appendChild(cardsFor(task));
  }

  function renderAll() {
    allEl.querySelectorAll(".code-grid").forEach(function (grid) {
      grid.innerHTML = "";
      grid.appendChild(cardsFor(taskById(grid.dataset.task)));
    });
  }

  // Table view on code.html: one row per program, one column per language.
  function renderTable() {
    var table = document.getElementById("codeTable");
    var langs = LANGS.filter(function (l) { return state.on[l.id]; });
    var html = '<thead><tr><th class="ct-prog">Program</th>';
    langs.forEach(function (l) {
      html += '<th class="' + l.cls + '"><span class="lang-dot"></span>' + l.name + "</th>";
    });
    html += "</tr></thead><tbody>";
    var num = 0;
    CATEGORIES.forEach(function (c) {
      html += '<tr class="ct-cat"><th colspan="' + (langs.length + 1) + '"><span>' + esc(c.name) + "</span></th></tr>";
      TASKS.filter(function (t) { return t.cat === c.id; }).forEach(function (t) {
        num++;
        html += '<tr id="row-' + t.id + '"><th class="ct-prog"><span class="task-num">' + (num < 10 ? "0" : "") + num + "</span>" +
          "<b>" + esc(t.title) + "</b>" +
          (t.out ? '<div class="ct-out">' + esc(t.out) + "</div>" : "") + "</th>";
        langs.forEach(function (l) {
          var s = snips[t.id + ":" + l.id];
          if (!s) { html += "<td></td>"; return; }
          var n = lineCount(s.code);
          html += '<td class="' + l.cls + '"><pre><code>' + highlight(s.code, l.id) + "</code></pre>" +
            '<div class="ct-meta">' + n + (n === 1 ? " line" : " lines") + "</div>" +
            (s.note ? '<div class="ct-note">' + esc(s.note) + "</div>" : "") +
            (s.res && s.res !== t.out ? '<div class="ct-res' + (s.bad ? " bad" : "") + '">' + esc(s.res) + "</div>" : "") +
            "</td>";
        });
        html += "</tr>";
      });
    });
    table.innerHTML = html + "</tbody>";
    watchRows();
  }

  // Highlight the current program in the left list while scrolling the table.
  var rowObserver = null;
  function watchRows() {
    if (!("IntersectionObserver" in window)) return;
    if (rowObserver) rowObserver.disconnect();
    var wrap = document.querySelector("#tableView .ct-wrap");
    rowObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting || state.view !== "table") return;
        var href = "#t-" + e.target.id.replace(/^row-/, "");
        document.querySelectorAll("#codeToc a").forEach(function (a) {
          a.classList.toggle("active", a.getAttribute("href") === href);
        });
      });
    }, { root: wrap || null, rootMargin: "-12% 0px -72% 0px" });
    document.querySelectorAll("#codeTable tr[id]").forEach(function (r) { rowObserver.observe(r); });
  }

  function renderView() {
    var tableEl = document.getElementById("tableView");
    if (!tableEl) return;
    allEl.hidden = state.view === "table";
    var docs = document.querySelector(".docs");
    if (docs) docs.classList.toggle("table-mode", state.view === "table");
    tableEl.hidden = state.view !== "table";
    document.querySelectorAll(".view-switch button").forEach(function (b) {
      var on = b.dataset.view === state.view;
      b.classList.toggle("on", on);
      b.setAttribute("aria-pressed", on);
    });
    updateCtTop();
  }

  function render() {
    renderToggles();
    if (tabsEl) renderTabs();
    if (allEl) {
      renderAll();
      if (document.getElementById("codeTable")) renderTable();
      renderView();
    }
  }

  LANGS.forEach(function (l) {
    var b = document.createElement("button");
    b.className = "lang-toggle " + l.cls;
    b.innerHTML = '<span class="lang-dot"></span>' + l.name;
    b.dataset.lang = l.id;
    b.addEventListener("click", function () {
      var count = Object.keys(state.on).filter(function (k) { return state.on[k]; }).length;
      if (state.on[l.id] && count <= 1) return; // keep at least one language
      state.on[l.id] = !state.on[l.id];
      try { localStorage.setItem("ink-compare-langs", JSON.stringify(state.on)); } catch (e) {}
      render();
    });
    togglesEl.appendChild(b);
  });

  if (tabsEl) {
    TAB_TASKS.forEach(function (id) {
      var t = taskById(id);
      var b = document.createElement("button");
      b.className = "task-tab";
      b.textContent = t.label;
      b.setAttribute("role", "tab");
      b.dataset.task = t.id;
      b.addEventListener("click", function () { state.task = t.id; renderTabs(); });
      tabsEl.appendChild(b);
    });
  }

  if (allEl) {
    var toc = document.getElementById("codeToc");
    var jump = document.getElementById("codeJump");
    var num = 0;
    CATEGORIES.forEach(function (c) {
      var tasks = TASKS.filter(function (t) { return t.cat === c.id; });
      var h = document.createElement("h2");
      h.className = "cat-title";
      h.id = "cat-" + c.id;
      h.textContent = c.name;
      allEl.appendChild(h);
      if (toc) {
        var th = document.createElement("div");
        th.className = "toc-cat";
        th.textContent = c.name;
        toc.appendChild(th);
      }
      var group = jump && document.createElement("optgroup");
      if (group) { group.label = c.name; jump.appendChild(group); }
      tasks.forEach(function (t) {
        num++;
        var sec = document.createElement("div");
        sec.className = "task-block";
        sec.id = "t-" + t.id;
        sec.innerHTML = '<div class="task-head"><span class="task-num">' + (num < 10 ? "0" : "") + num + "</span><div><h3>" + esc(t.title) + "</h3><p>" + esc(t.desc) + "</p></div></div>" +
          '<div class="code-grid" data-task="' + t.id + '"></div>';
        allEl.appendChild(sec);
        if (toc) {
          var a = document.createElement("a");
          a.href = "#t-" + t.id;
          a.textContent = t.title;
          toc.appendChild(a);
        }
        if (group) {
          var o = document.createElement("option");
          o.value = "t-" + t.id;
          o.textContent = num + ". " + t.title;
          group.appendChild(o);
        }
      });
    });
    if (jump) jump.addEventListener("change", function () { jumpTo(jump.value, true); });
    if (toc) toc.addEventListener("click", function (e) {
      var a = e.target.closest("a");
      if (!a) return;
      e.preventDefault();
      jumpTo(a.getAttribute("href").slice(1), true);
    });
    document.querySelectorAll(".view-switch button").forEach(function (b) {
      b.addEventListener("click", function () {
        state.view = b.dataset.view;
        try { localStorage.setItem("ink-code-view", state.view); } catch (e) {}
        renderView();
      });
    });
    renderView();
    var countEl = document.getElementById("taskCount");
    if (countEl) countEl.textContent = TASKS.length;
    window.addEventListener("resize", updateCtTop);
    window.addEventListener("load", updateCtTop);
  }

  fetch("assets/snippets.html")
    .then(function (r) { return r.text(); })
    .then(function (html) {
      var doc = new DOMParser().parseFromString(html, "text/html");
      doc.querySelectorAll("script.snip").forEach(function (s) {
        snips[s.dataset.task + ":" + s.dataset.lang] = {
          code: s.textContent.replace(/^\n+|\s+$/g, ""),
          res: s.dataset.res || null,
          note: s.dataset.note || null,
          bad: s.dataset.bad === "1"
        };
      });
      render();
      if (allEl && location.hash) jumpTo(location.hash.slice(1), false);
    })
    .catch(function () {
      var msg = '<p style="color:var(--text-muted)">The code samples could not be loaded. Please refresh the page.</p>';
      if (tabsEl) document.getElementById("codeGrid").innerHTML = msg;
      if (allEl) allEl.insertAdjacentHTML("afterbegin", msg);
    });

  renderToggles();
})();
