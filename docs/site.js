// thumbs-out landing page: copy buttons and the scroll tour (laptop opens → desktop → panel tour).
(() => {
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  document.querySelectorAll("button[data-copy]").forEach((button) => {
    button.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(button.dataset.copy);
        button.textContent = "Copied";
        button.classList.add("copied");
      } catch {
        button.textContent = "Press ⌘C";
      }
      setTimeout(() => {
        button.textContent = "Copy";
        button.classList.remove("copied");
      }, 1800);
    });
  });

  setUpCompatibilityCheck();

  const intro = document.querySelector(".intro");
  if (!intro || reducedMotion) return; // The static tour already reads top to bottom.

  const copy = intro.querySelector(".intro-copy");
  const laptop = intro.querySelector(".laptop");
  const lid = intro.querySelector(".screen-lid");
  const shadow = intro.querySelector(".floor-shadow");
  const desktop = intro.querySelector(".desktop");
  const panelWrap = intro.querySelector(".panel-wrap");
  const icon = intro.querySelector(".mb-icon");
  const cursor = intro.querySelector(".cursor");
  const dots = [...intro.querySelectorAll(".tour-progress i")];

  intro.classList.add("is-live");

  // Scroll progress (0–1) at which each phase starts and ends.
  const PHASE = { open: [0.02, 0.13], zoom: [0.13, 0.23], reveal: [0.205, 0.245], point: [0.245, 0.285], click: 0.29, tour: [0.3, 0.985] };
  const STEPS = 6;

  const clamp01 = (v) => Math.min(1, Math.max(0, v));
  const progressIn = ([from, to], p) => clamp01((p - from) / (to - from));
  const ease = (t) => 1 - Math.pow(1 - t, 3);
  const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
  const mix = (a, b, t) => a + (b - a) * t;

  let geometry = null;
  // ?preview=0.4 freezes the tour at that point without scrolling, for screenshots.
  const previewParam = new URLSearchParams(location.search).get("preview");
  const preview = previewParam !== null && Number(previewParam) >= 0 && Number(previewParam) <= 1 ? Number(previewParam) : null;

  // Measures the layout once per resize; transforms are cleared while measuring.
  function measure() {
    laptop.style.transform = "none";
    lid.style.transform = "none";
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const width = laptop.offsetWidth;
    const lidHeight = lid.offsetHeight;
    // The closed laptop starts small and low, then grows and rises as the lid opens.
    const narrow = vw <= 980;
    const startScale = vw < 760 ? 0.82 : 0.6;
    const hingeStart = vh * (vw < 760 ? 0.88 : 0.84);
    const hingeOpen = vh * (vw < 760 ? 0.74 : 0.76);
    const screenWidth = width * 0.956;
    const screenHeight = lidHeight * 0.928;
    const zoom = Math.max(vw / screenWidth, vh / screenHeight) * 1.03;

    // Panel sits under the menu bar icon, kept on screen.
    const iconRect = icon.getBoundingClientRect();
    const panelWidth = panelWrap.offsetHeight * (684 / 1280);
    const panelLeft = narrow
      ? (vw - panelWidth) / 2
      : Math.min(vw - panelWidth - 16, Math.max(16, iconRect.left + iconRect.width / 2 - panelWidth / 2));
    panelWrap.style.left = `${panelLeft}px`;
    panelWrap.style.width = `${panelWidth}px`;

    geometry = {
      vw, vh, lidHeight, zoom, startScale, hingeStart, hingeOpen,
      cursorFrom: { x: vw * 0.42, y: vh * 0.62 },
      cursorTo: { x: iconRect.left + iconRect.width / 2 - 4, y: iconRect.top + iconRect.height / 2 - 2 },
    };
    laptop.style.transformOrigin = `50% ${lidHeight / 2}px`;
  }

  function render() {
    ticking = false;
    if (!geometry) measure();
    const g = geometry;
    const rect = intro.getBoundingClientRect();
    const scrollable = intro.offsetHeight - g.vh;
    const p = preview ?? clamp01(-rect.top / scrollable);
    intro.dataset.progress = p.toFixed(3);

    // 1. Lid opens, headline steps aside.
    const open = easeInOut(progressIn(PHASE.open, p));
    const zoomT = easeInOut(progressIn(PHASE.zoom, p));
    // −87° folds the lid down onto the keyboard (raised a hair so the two planes don't fight);
    // slightly positive leans the open screen back.
    const lidAngle = mix(-87, 8, open) * (1 - zoomT);
    const tilt = mix(26, 14, open) * (1 - zoomT);
    lid.style.transform = `rotateX(${lidAngle}deg)`;
    // Pick the visible face ourselves; backface-visibility isn't reliable in every 3D context.
    lid.classList.toggle("show-back", lidAngle < -45);

    const copyT = progressIn([0.0, 0.11], p);
    copy.style.opacity = String(1 - copyT);
    copy.style.transform = `translateY(${-60 * ease(copyT)}px)`;
    copy.style.visibility = copyT >= 1 ? "hidden" : "visible";

    // 2. Camera zooms into the screen. Positions are for the lid's centre (the transform origin).
    const hinge = mix(g.hingeStart, g.hingeOpen, open);
    const openScale = mix(g.startScale, 1, open);
    const scale = zoomT > 0 ? mix(1, g.zoom, zoomT) : openScale;
    const centerY = zoomT > 0 ? mix(g.hingeOpen - g.lidHeight / 2, g.vh / 2, zoomT) : hinge - (g.lidHeight / 2) * openScale;
    // Negative tilt: the camera looks down on the laptop, as if it were on a desk.
    laptop.style.transform = `translate(-50%, ${centerY - g.lidHeight / 2}px) scale(${scale}) rotateX(${-tilt}deg)`;
    // The shadow sits under the front edge, which moves back toward the hinge as the lid opens.
    const frontEdge = hinge + g.lidHeight * openScale * mix(0.62, 0.5, open);
    shadow.style.transform = `translate(-50%, ${frontEdge - 45}px) scale(${openScale})`;
    shadow.style.opacity = String(1 - zoomT);

    // 3. The desktop takes over from the zoomed screen.
    const reveal = progressIn(PHASE.reveal, p);
    desktop.style.opacity = String(reveal);
    desktop.classList.toggle("is-visible", reveal > 0);
    laptop.style.opacity = String(1 - progressIn([PHASE.reveal[1] - 0.01, PHASE.reveal[1] + 0.01], p));
    document.body.classList.toggle("on-desktop", reveal > 0.5 && p < 0.995);

    // 4. The cursor moves to the thumb and clicks; the panel drops down.
    const point = easeInOut(progressIn(PHASE.point, p));
    const clicked = p >= PHASE.click;
    const press = clicked && p < PHASE.click + 0.008 ? 0.85 : 1;
    const cx = mix(g.cursorFrom.x, g.cursorTo.x, point);
    const cy = mix(g.cursorFrom.y, g.cursorTo.y, point);
    cursor.style.transform = `translate(${cx}px, ${cy}px) scale(${press})`;
    cursor.style.opacity = String(Math.min(progressIn([PHASE.point[0] - 0.01, PHASE.point[0]], p), 1 - progressIn([PHASE.click + 0.02, PHASE.click + 0.035], p)));
    desktop.classList.toggle("panel-open", clicked);

    // 5. Six tour steps.
    const tourT = progressIn(PHASE.tour, p);
    const step = clicked ? Math.min(STEPS - 1, Math.floor(tourT * STEPS)) : -1;
    if (desktop.dataset.step !== String(step)) {
      desktop.dataset.step = String(step);
      dots.forEach((dot, index) => dot.classList.toggle("is-current", index === step));
    }
  }

  let ticking = false;
  const requestRender = () => {
    if (!ticking) {
      ticking = true;
      requestAnimationFrame(render);
    }
  };
  window.addEventListener("scroll", requestRender, { passive: true });
  window.addEventListener("resize", () => { geometry = null; requestRender(); });

  render();

  // ---------- Compatibility check ----------
  // Browsers hide some system details on purpose. Chromium browsers share the macOS version and
  // CPU architecture through client hints; others don't, so the GPU name is used to spot the chip,
  // and anything still unknown points to a Terminal check.
  function setUpCompatibilityCheck() {
    const root = document.getElementById("compat");
    if (!root) return;
    const button = root.querySelector(".compat-button");
    const result = root.querySelector(".compat-result");
    const verdict = root.querySelector(".compat-verdict");
    const list = root.querySelector(".compat-list");
    const terminal = root.querySelector(".compat-terminal");
    const MIN_MACOS = 15;

    button.addEventListener("click", async () => {
      button.disabled = true;
      const checks = await runChecks();
      render(checks);
      button.disabled = false;
      button.textContent = "Check again";
    });

    async function runChecks() {
      const ua = navigator.userAgent;
      const hints = navigator.userAgentData;
      const platform = hints?.platform || navigator.platform || "";
      const isIPad = /Macintosh/.test(ua) && navigator.maxTouchPoints > 1;
      const isMac = /mac/i.test(platform) && !isIPad;

      let architecture = null;
      let macVersion = null;
      if (hints?.getHighEntropyValues) {
        try {
          const values = await hints.getHighEntropyValues(["architecture", "platformVersion"]);
          architecture = values.architecture || null;
          macVersion = values.platformVersion || null;
        } catch { /* The browser declined; fall back below. */ }
      }

      const gpu = graphicsRenderer();
      const chipMatch = gpu && gpu.match(/Apple (M\d+(?: (?:Pro|Max|Ultra))?)/);
      let silicon = { tone: "unknown", detail: "Your browser doesn't say which chip you have." };
      if (architecture === "arm" || chipMatch) {
        silicon = { tone: "pass", detail: chipMatch ? `Apple ${chipMatch[1]}` : "Apple Silicon" };
      } else if (architecture === "x86" || (gpu && /Intel|AMD|Radeon|NVIDIA/i.test(gpu))) {
        silicon = { tone: "fail", detail: "This looks like an Intel Mac. thumbs-out needs Apple Silicon (M1 or later)." };
      } else if (gpu && /Apple GPU/i.test(gpu)) {
        silicon = { tone: "pass", detail: "Apple GPU, so almost certainly Apple Silicon." };
      }

      let macOS = { tone: "unknown", detail: "Your browser hides the macOS version." };
      const major = macVersion ? parseInt(macVersion, 10) : NaN;
      if (Number.isFinite(major) && major >= 10) {
        macOS = major >= MIN_MACOS
          ? { tone: "pass", detail: `macOS ${macVersion.replace(/\.0$/, "")}` }
          : { tone: "fail", detail: `macOS ${macVersion}. thumbs-out needs macOS ${MIN_MACOS} or later.` };
      }

      return { isMac, silicon, macOS };
    }

    function graphicsRenderer() {
      try {
        const gl = document.createElement("canvas").getContext("webgl");
        if (!gl) return null;
        const info = gl.getExtension("WEBGL_debug_renderer_info");
        return String(gl.getParameter(info ? info.UNMASKED_RENDERER_WEBGL : gl.RENDERER));
      } catch {
        return null;
      }
    }

    function render({ isMac, silicon, macOS }) {
      list.replaceChildren();
      result.hidden = false;
      if (!isMac) {
        setVerdict("fail", "This isn't a Mac. Open this page on your Mac to check it.");
        terminal.hidden = true;
        return;
      }
      addRow("pass", "A Mac", "thumbs-out is a macOS menu bar app.");
      addRow(silicon.tone, "Apple Silicon", silicon.detail);
      addRow(macOS.tone, `macOS ${MIN_MACOS} or later`, macOS.detail);

      const tones = [silicon.tone, macOS.tone];
      if (tones.includes("fail")) {
        setVerdict("fail", "Not compatible, sorry.");
      } else if (tones.includes("unknown")) {
        setVerdict("unknown", "Probably fine. Confirm the details below.");
      } else {
        setVerdict("pass", "Good to go. Thumbs up!");
      }
      terminal.hidden = !tones.includes("unknown");
    }

    function setVerdict(tone, text) {
      verdict.dataset.tone = tone;
      verdict.textContent = text;
    }

    function addRow(tone, title, detail) {
      const item = document.createElement("li");
      const icon = document.createElement("span");
      icon.className = "compat-icon";
      icon.dataset.tone = tone;
      icon.textContent = tone === "pass" ? "✓" : tone === "fail" ? "✕" : "?";
      icon.setAttribute("aria-label", tone === "pass" ? "Yes" : tone === "fail" ? "No" : "Unknown");
      const text = document.createElement("div");
      const strong = document.createElement("strong");
      strong.textContent = title;
      const small = document.createElement("span");
      small.className = "detail";
      small.textContent = detail;
      text.append(strong, small);
      item.append(icon, text);
      list.append(item);
    }
  }
})();
