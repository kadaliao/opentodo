// OpenTodo 产品页的交互：最新版本的下载地址、截图的浅色 / 深色、
// 标签页切换、快速添加的输入演示、拷贝 Homebrew 命令。
(() => {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ---------- 最新版本 ----------
  // 页面里写的是发布时的版本；能连上 GitHub 时换成最新一版的 DMG。
  fetch("https://api.github.com/repos/kadaliao/opentodo/releases/latest", {
    headers: { Accept: "application/vnd.github+json" },
  })
    .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
    .then((release) => {
      const assets = release.assets || [];
      const dmg = assets.find((a) => /\.dmg$/i.test(a.name));
      if (!dmg) return;
      const version = String(release.tag_name || "").replace(/^v/, "");
      document.querySelectorAll(".js-dmg").forEach((a) => (a.href = dmg.browser_download_url));
      if (version) document.querySelectorAll("[data-version]").forEach((el) => (el.textContent = version));
      document.querySelectorAll("[data-size]").forEach((el) => (el.textContent = `${Math.round(dmg.size / 1e6)} MB`));
      const sums = assets.find((a) => a.name === "SHA256SUMS");
      if (sums) document.querySelectorAll(".js-sums").forEach((a) => (a.href = sums.browser_download_url));
    })
    .catch(() => {});

  // ---------- 主截图的浅色 / 深色 ----------
  // 没点过按钮时跟着系统外观（CSS 按 prefers-color-scheme 显示），这里只让按钮的按下状态对上；
  // 点过以后用 data-appearance 定住，系统再切换也不变。
  const heroShot = document.querySelector(".hero-shot");
  const lookButtons = document.querySelectorAll("[data-look]");
  const systemDark = window.matchMedia("(prefers-color-scheme: dark)");
  const pressLook = (look) => lookButtons.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.look === look)));
  const followSystem = () => {
    if (!heroShot.dataset.appearance) pressLook(systemDark.matches ? "dark" : "light");
  };
  followSystem();
  systemDark.addEventListener("change", followSystem);
  lookButtons.forEach((button) => {
    button.addEventListener("click", () => {
      heroShot.dataset.appearance = button.dataset.look;
      pressLook(button.dataset.look);
    });
  });

  // ---------- 标签页 ----------
  document.querySelectorAll("[data-switcher]").forEach((switcher) => {
    const tabs = [...switcher.querySelectorAll('[role="tab"]')];
    const select = (tab, focus) => {
      tabs.forEach((t) => {
        const on = t === tab;
        t.setAttribute("aria-selected", String(on));
        t.tabIndex = on ? 0 : -1;
        document.getElementById(t.getAttribute("aria-controls")).hidden = !on;
      });
      if (focus) tab.focus();
    };
    tabs.forEach((tab, i) => {
      tab.addEventListener("click", () => select(tab, false));
      tab.addEventListener("keydown", (e) => {
        const last = tabs.length - 1;
        const next = { ArrowRight: i === last ? 0 : i + 1, ArrowLeft: i === 0 ? last : i - 1, Home: 0, End: last }[e.key];
        if (next === undefined) return;
        e.preventDefault();
        select(tabs[next], true);
      });
    });
  });

  // ---------- 快速添加演示 ----------
  // 例句和识别结果都来自应用的解析测试（QuickAddParserTests）。
  const examples = [
    {
      text: "明天下午3点开会 #工作 !高",
      tokens: [
        { match: "明天下午3点", kind: "date", min: 2 },
        { match: "#工作", kind: "tag", min: 2 },
        { match: "!高", kind: "prio", min: 2 },
      ],
      title: "开会",
      high: true,
      chips: [
        { kind: "date", text: "明天 15:00" },
        { kind: "tag", text: "工作" },
        { kind: "prio", text: "高优先级" },
      ],
    },
    {
      text: "每周一三五跑步",
      tokens: [{ match: "每周一三五", kind: "date", min: 3 }],
      title: "跑步",
      chips: [{ kind: "repeat", text: "每周一、三、五" }],
    },
    {
      text: "每月15号还信用卡",
      tokens: [{ match: "每月15号", kind: "date", min: 4 }],
      title: "还信用卡",
      chips: [{ kind: "repeat", text: "每月 15 日" }],
    },
    {
      text: "上午9点到11点半 写方案",
      tokens: [{ match: "上午9点到11点半", kind: "date", min: 4 }],
      title: "写方案",
      chips: [{ kind: "date", text: "09:00 – 11:30" }],
    },
  ];

  const qa = document.querySelector("[data-qa]");
  if (qa) {
    const textEl = qa.querySelector(".qa-text");
    const result = qa.querySelector(".qa-result");
    const titleEl = qa.querySelector(".qa-title");
    const chipsEl = qa.querySelector(".qa-chips");
    const checkEl = qa.querySelector(".qa-check");
    const sayEl = qa.querySelector("[data-qa-say]");
    const buttons = [...qa.querySelectorAll(".qa-examples button")];
    let run = 0;

    const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

    const spansOf = (ex) =>
      ex.tokens
        .map((t) => {
          const from = ex.text.indexOf(t.match);
          return { from, to: from + t.match.length, kind: t.kind, min: t.min };
        })
        .sort((a, b) => a.from - b.from);

    // 打到第 n 个字时的样子：认出来的部分（够长了才算认出）标上颜色。
    const renderTyped = (ex, n) => {
      let html = "";
      let at = 0;
      for (const s of spansOf(ex)) {
        if (s.from >= n) break;
        html += esc(ex.text.slice(at, s.from));
        const end = Math.min(n, s.to);
        const part = esc(ex.text.slice(s.from, end));
        html += end - s.from >= s.min ? `<span class="t-${s.kind}">${part}</span>` : part;
        at = end;
      }
      html += esc(ex.text.slice(at, n));
      textEl.innerHTML = html;
    };

    const renderResult = (ex) => {
      titleEl.textContent = ex.title;
      checkEl.classList.toggle("is-high", !!ex.high);
      chipsEl.innerHTML = ex.chips.map((c) => `<span class="chip chip-${c.kind}">${esc(c.text)}</span>`).join("");
      result.classList.add("is-shown");
      sayEl.textContent = `输入“${ex.text}”，记成任务“${ex.title}”：${ex.chips.map((c) => c.text).join("，")}`;
    };

    const wait = (ms) => new Promise((r) => setTimeout(r, ms));

    const play = async (index) => {
      const id = ++run;
      const ex = examples[index];
      buttons.forEach((b, i) => b.setAttribute("aria-pressed", String(i === index)));
      result.classList.remove("is-shown");
      if (reduceMotion) {
        renderTyped(ex, ex.text.length);
        renderResult(ex);
        return;
      }
      renderTyped(ex, 0);
      await wait(250);
      for (let n = 1; n <= ex.text.length; n++) {
        if (id !== run) return;
        renderTyped(ex, n);
        await wait(ex.text[n - 1] === " " ? 60 : 105 + Math.random() * 60);
      }
      await wait(380);
      if (id === run) renderResult(ex);
    };

    buttons.forEach((b, i) => b.addEventListener("click", () => play(i)));

    if ("IntersectionObserver" in window) {
      const io = new IntersectionObserver(
        (entries) => {
          if (entries.some((e) => e.isIntersecting)) {
            io.disconnect();
            play(0);
          }
        },
        { threshold: 0.6 }
      );
      io.observe(qa);
    } else {
      play(0);
    }
  }

  // ---------- 拷贝命令 ----------
  document.querySelectorAll("[data-copy]").forEach((button) => {
    button.addEventListener("click", async () => {
      const source = document.querySelector(button.dataset.copy);
      try {
        await navigator.clipboard.writeText(source.textContent.trim());
        button.textContent = "已拷贝";
      } catch {
        const range = document.createRange();
        range.selectNodeContents(source);
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
        button.textContent = "已选中";
      }
      setTimeout(() => (button.textContent = "拷贝"), 1800);
    });
  });
})();
