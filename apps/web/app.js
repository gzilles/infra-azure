// Security Posture Dashboard — first page (vanilla JS, no build step, no external dependencies).
// Data comes from the Posture API (Azure Function) or, with ?mock=1, from mock-data.js.
// All data is written with textContent / SVG attributes — never innerHTML — so API content cannot inject markup.
(function () {
  "use strict";

  const cfg = window.APP_CONFIG || {};
  const params = new URLSearchParams(location.search);
  const MOCK = params.get("mock") === "1" || cfg.mock === true;
  const DEV = cfg.authMode === "dev-anonymous" || MOCK;
  const ORG_RE = /^org-[a-z0-9-]{1,40}$/;
  let org = params.get("org") || cfg.defaultOrg || "org-a";
  if (!ORG_RE.test(org)) org = cfg.defaultOrg || "org-a";
  let selectedKey = null;

  const STATUS = {
    good: { label: "Healthy", icon: "✓" },
    warning: { label: "Watch", icon: "!" },
    serious: { label: "At risk", icon: "▲" },
    critical: { label: "Critical", icon: "✕" },
  };
  const CONTROL_STATUS = {
    ok: { cls: "good", label: "On track", icon: "✓" },
    "at-risk": { cls: "warning", label: "At risk", icon: "!" },
    overdue: { cls: "critical", label: "Overdue", icon: "✕" },
  };
  const statusFromScore = (s) => (s >= 80 ? "good" : s >= 65 ? "warning" : s >= 50 ? "serious" : "critical");

  // ---------- DOM helpers ----------
  const $ = (id) => document.getElementById(id);
  function el(tag, attrs, ...children) {
    const n = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (k === "class") n.className = v;
      else if (k === "text") n.textContent = v;
      else if (k.startsWith("on")) n.addEventListener(k.slice(2), v);
      else n.setAttribute(k, v);
    }
    for (const c of children) if (c != null) n.append(c);
    return n;
  }
  const SVGNS = "http://www.w3.org/2000/svg";
  function svg(tag, attrs) {
    const n = document.createElementNS(SVGNS, tag);
    for (const [k, v] of Object.entries(attrs || {})) n.setAttribute(k, v);
    return n;
  }
  function badge(cls, icon, label) {
    return el("span", { class: "badge " + cls }, el("span", { class: "dot", "aria-hidden": "true", text: icon }), label);
  }
  const fmtDelta = (d) => (d > 0 ? "▲ +" + d : d < 0 ? "▼ " + d : "● 0");
  const fmtDate = (iso) => {
    const d = new Date(iso);
    // timeZone UTC: "2026-09-15" é lido como meia-noite UTC; no fuso local (ex.: UTC-3) viraria o dia anterior.
    return isNaN(d) ? iso : d.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric", timeZone: "UTC" });
  };

  // ---------- Tooltip ----------
  const tip = $("tooltip");
  function showTip(evt, title, lines) {
    tip.replaceChildren(el("strong", { text: title }), ...lines.map((l) => el("div", { text: l })));
    tip.hidden = false;
    const pad = 14, r = tip.getBoundingClientRect();
    let x = evt.clientX + pad, y = evt.clientY + pad;
    if (x + r.width > innerWidth - 8) x = evt.clientX - r.width - pad;
    if (y + r.height > innerHeight - 8) y = evt.clientY - r.height - pad;
    tip.style.left = x + "px"; tip.style.top = y + "px";
  }
  const hideTip = () => (tip.hidden = true);

  // ---------- Data access ----------
  async function api(path) {
    if (MOCK) {
      await new Promise((r) => setTimeout(r, 150));
      const data = window.MOCK_DATA[org];
      if (!data) throw new Error("Unknown organization in mock data: " + org);
      if (path.startsWith("/posture")) return data.posture;
      const m = path.match(/^\/indicators\/([a-z0-9-]+)\/controls/);
      if (m) {
        const ind = data.posture.indicators.find((i) => i.key === m[1]);
        return { indicator: { key: ind.key, name: ind.name }, controls: data.controls[m[1]] || [] };
      }
      throw new Error("No mock for " + path);
    }
    const sep = path.includes("?") ? "&" : "?";
    const url = cfg.apiBase + path + (DEV ? sep + "org=" + encodeURIComponent(org) : "");
    const res = await fetch(url, { signal: AbortSignal.timeout(cfg.timeoutMs || 15000), headers: { Accept: "application/json" } });
    if (!res.ok) throw new Error("API " + res.status + " " + res.statusText + " on " + path);
    return res.json();
  }

  // ---------- Rendering ----------
  function renderHero(p) {
    $("org-name").textContent = p.organization.name;
    $("updated-at").textContent = "Data as of " + fmtDate(p.updatedAt);
    $("score").textContent = p.score;
    const d = p.score - p.previousScore;
    $("score-delta").replaceChildren(el("strong", { text: fmtDelta(d) }), " vs last week (" + p.previousScore + ")");
    const st = p.status || statusFromScore(p.score);
    $("score-status").replaceChildren(badge(st, STATUS[st].icon, STATUS[st].label));
  }

  function barEl(ind) {
    // HTML bar: anchored at the baseline (square left end), 4px rounded data end, last-week tick
    const track = el("span", { class: "bar-track", role: "img",
      "aria-label": `${ind.name}: ${ind.score} of 100, last week ${ind.previousScore}` });
    const fill = el("span", { class: "bar-fill" }); fill.style.width = Math.max(0, Math.min(100, ind.score)) + "%";
    const tick = el("span", { class: "bar-tick" }); tick.style.left = Math.max(0, Math.min(100, ind.previousScore)) + "%";
    track.append(fill, tick);
    return track;
  }

  function sparkSvg(ind) {
    const W = 110, H = 30, pad = 4, t = ind.trend || [];
    const s = svg("svg", { viewBox: `0 0 ${W} ${H}`, height: H, role: "img",
      "aria-label": `${ind.name}, last ${t.length} weeks: ${t.join(", ")}` });
    if (t.length < 2) return s;
    const min = Math.min(...t) - 2, max = Math.max(...t) + 2;
    const X = (i) => pad + (i * (W - 2 * pad)) / (t.length - 1);
    const Y = (v) => H - pad - ((v - min) / (max - min || 1)) * (H - 2 * pad);
    s.append(svg("polyline", { points: t.map((v, i) => `${X(i)},${Y(v)}`).join(" "), fill: "none",
      stroke: "var(--series-1)", "stroke-width": 2, "stroke-linejoin": "round", "stroke-linecap": "round" }));
    const last = t.length - 1;
    s.append(svg("circle", { cx: X(last), cy: Y(t[last]), r: 4, fill: "var(--series-1)", stroke: "var(--surface-1)", "stroke-width": 2 }));
    const guide = svg("line", { y1: 0, y2: H, stroke: "var(--text-muted)", "stroke-width": 1, visibility: "hidden" });
    s.append(guide);
    s.addEventListener("pointermove", (e) => {
      const rect = s.getBoundingClientRect();
      const i = Math.max(0, Math.min(last, Math.round(((e.clientX - rect.left) / rect.width * W - pad) / ((W - 2 * pad) / last))));
      guide.setAttribute("x1", X(i)); guide.setAttribute("x2", X(i)); guide.setAttribute("visibility", "visible");
      const weeksAgo = last - i;
      showTip(e, ind.name, [(weeksAgo === 0 ? "This week" : weeksAgo + (weeksAgo === 1 ? " week ago" : " weeks ago")) + ": " + t[i]]);
    });
    s.addEventListener("pointerleave", () => { guide.setAttribute("visibility", "hidden"); hideTip(); });
    return s;
  }

  function renderIndicators(p) {
    const list = $("indicators");
    const sorted = [...p.indicators].sort((a, b) => a.score - b.score);
    list.replaceChildren(...sorted.map((ind) => {
      const st = ind.status || statusFromScore(ind.score);
      const d = ind.score - ind.previousScore;
      const bar = el("span", { class: "bar" }, barEl(ind));
      bar.addEventListener("pointermove", (e) => showTip(e, ind.name, ["Score: " + ind.score + " / 100", "Last week: " + ind.previousScore + " (" + fmtDelta(d) + ")", "Status: " + STATUS[st].label]));
      bar.addEventListener("pointerleave", hideTip);
      const btn = el("button", { class: "ind-row", type: "button", "aria-pressed": String(ind.key === selectedKey), "data-key": ind.key,
        onclick: () => selectIndicator(ind.key) },
        el("span", { class: "ind-name", text: ind.name }),
        bar,
        el("span", { class: "ind-score", text: String(ind.score) }),
        el("span", { class: "ind-delta", text: fmtDelta(d) }),
        el("span", { class: "ind-status" }, badge(st, STATUS[st].icon, STATUS[st].label)),
        el("span", { class: "spark" }, sparkSvg(ind)),
      );
      return el("li", {}, btn);
    }));
  }

  async function selectIndicator(key) {
    selectedKey = key;
    document.querySelectorAll(".ind-row").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.key === key)));
    const body = $("controls").tBodies[0];
    body.classList.add("loading");
    try {
      const data = await api("/indicators/" + encodeURIComponent(key) + "/controls");
      $("ctl-title").textContent = "Controls — " + data.indicator.name;
      const order = { overdue: 0, "at-risk": 1, ok: 2 };
      const rows = [...data.controls].sort((a, b) => (order[a.status] ?? 3) - (order[b.status] ?? 3));
      const count = (s) => rows.filter((c) => c.status === s).length;
      $("ctl-summary").textContent = `${count("overdue")} overdue · ${count("at-risk")} at risk · ${count("ok")} on track`;
      body.replaceChildren(...rows.map((c) => {
        const cs = CONTROL_STATUS[c.status] || { cls: "warning", label: c.status, icon: "?" };
        return el("tr", {},
          el("td", { class: "id", text: c.id }),
          el("td", { text: c.name }),
          el("td", { text: c.owner }),
          el("td", { class: "date", text: fmtDate(c.dueDate) }),
          el("td", {}, badge(cs.cls, cs.icon, cs.label)));
      }));
    } catch (err) {
      body.replaceChildren(el("tr", {}, el("td", { colspan: 5, text: "Could not load the controls: " + err.message })));
    } finally {
      body.classList.remove("loading");
    }
  }

  async function load() {
    $("error").hidden = true;
    $("content").hidden = false;
    $("content").classList.add("loading");
    try {
      const p = await api("/posture");
      renderHero(p);
      renderIndicators(p);
      const worst = [...p.indicators].sort((a, b) => a.score - b.score)[0];
      await selectIndicator(selectedKey && p.indicators.some((i) => i.key === selectedKey) ? selectedKey : worst.key);
    } catch (err) {
      $("content").hidden = true;
      $("error").hidden = false;
      $("error-detail").textContent = err.name === "TimeoutError" ? "The API did not answer within " + (cfg.timeoutMs / 1000) + " s." : err.message;
      $("org-name").textContent = "Unavailable";
    } finally {
      $("content").classList.remove("loading");
    }
  }

  // ---------- Init ----------
  if (DEV) {
    $("dev-banner").hidden = false;
    $("mode-label").textContent = MOCK ? "Sample data (mock)" : "Live API";
    const sel = $("org-select");
    sel.value = org;
    sel.addEventListener("change", () => {
      org = sel.value;
      const u = new URL(location.href); u.searchParams.set("org", org); history.replaceState(null, "", u);
      load();
    });
  }
  $("retry").addEventListener("click", load);
  load();
})();
