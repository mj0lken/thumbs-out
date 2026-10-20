// thumbs-out landing page: copy buttons, the snapping grace meter, and reveal-on-scroll.
(() => {
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Copy the Homebrew command.
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

  // Grace meter: same stops as the app (GracePeriodScale.minutes).
  const stops = [0, 1, 2, 5, 10, 15, 20, 30, 60, 120, 240];
  const meter = document.getElementById("grace");
  const output = document.getElementById("grace-value");
  const label = (m) => (m < 60 ? `${m}m` : `${m / 60}h`);
  const spoken = (m) => (m === 0 ? "No grace period" : m < 60 ? `${m} minutes` : `${m / 60} hour${m === 60 ? "" : "s"}`);
  const updateMeter = () => {
    const minutes = stops[Number(meter.value)];
    output.textContent = label(minutes);
    meter.setAttribute("aria-valuetext", spoken(minutes));
    meter.style.setProperty("--fill", `${(Number(meter.value) / (stops.length - 1)) * 100}%`);
  };
  if (meter && output) {
    meter.addEventListener("input", updateMeter);
    updateMeter();
  }

  // Video: respect reduced motion by showing controls instead of autoplaying.
  const video = document.querySelector(".demo-frame video");
  if (video && reducedMotion) {
    video.removeAttribute("autoplay");
    video.pause();
    video.controls = true;
  }

  // Reveal sections as they scroll into view; also drives the lid fallback animation.
  const targets = document.querySelectorAll(".trend, .step, .meter-card, .tier, .collage, .install-option");
  if (reducedMotion || !("IntersectionObserver" in window)) {
    targets.forEach((el) => el.classList.add("in-view"));
    return;
  }
  targets.forEach((el) => {
    if (!el.classList.contains("trend")) el.classList.add("reveal");
  });
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("in-view");
        observer.unobserve(entry.target);
      });
    },
    { threshold: 0.2 }
  );
  targets.forEach((el) => observer.observe(el));
})();
