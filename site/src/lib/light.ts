import shader from "./light.wgsl";

// The hero's deploy light, drawn with vgpu (WebGPU). Its colour follows the deploy ticker: amber while
// building, green when live, red when a build fails. No WebGPU, reduced motion or an offscreen hero all
// degrade to less, never to broken: without the GPU the grid and page carry the hero.

export type DeployState = "building" | "live" | "failed";
const TINTS: Record<DeployState, [number, number, number]> = {
  building: [1.0, 0.68, 0.3],
  live: [0.34, 0.92, 0.55],
  failed: [1.0, 0.38, 0.32],
};
let wanted: [number, number, number] = [...TINTS.building];
let kickLight = () => {};

/** Called by the ticker on every state change; the light eases to the new colour. */
export function setLightState(state: DeployState) {
  wanted = [...TINTS[state]];
  kickLight();
}

export async function mountLight(canvas: HTMLCanvasElement) {
  if (!("gpu" in navigator)) return;
  try {
    const { init, surface, effect, frame } = await import("vgpu");
    const gpu = await init({ label: "deployedyet-light" });
    const out = surface(gpu, canvas, { alphaMode: "premultiplied", dpr: Math.min(devicePixelRatio || 1, 1.5) });
    const fx = effect(gpu, shader, { label: "deploy-light" });

    const still = matchMedia("(prefers-reduced-motion: reduce)");
    let visible = true;
    let raf = 0;
    let last = 0;
    const start = performance.now();
    const tint: [number, number, number] = [...wanted];

    const draw = (now: number) => {
      const t = still.matches ? 0 : (now - start) / 1000;
      for (let i = 0; i < 3; i++) tint[i] += (wanted[i] - tint[i]) * (still.matches ? 1 : 0.05);
      fx.set({
        params: {
          resolution: [canvas.clientWidth, canvas.clientHeight],
          pointer: [0.5, 0.3], // held at centre: the beam stays put rather than following the mouse
          tint: [tint[0], tint[1], tint[2], 1],
          time: t,
          intensity: 1,
          _pad: [0, 0],
        },
      });
      frame(gpu, (f) => f.pass(out, fx)); // surfaces only accept draws inside a frame
    };

    const loop = (now: number) => {
      raf = 0;
      if (!visible) return;
      if (now - last > 33) { // ~30fps is plenty for slow light
        last = now;
        draw(now);
      }
      if (!still.matches) raf = requestAnimationFrame(loop);
    };
    const kick = () => {
      if (!raf && visible) raf = requestAnimationFrame(loop);
    };

    new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      kick();
    }).observe(canvas);
    new ResizeObserver(() => {
      if (still.matches) requestAnimationFrame(draw);
      else kick();
    }).observe(canvas);
    still.addEventListener("change", kick);
    kickLight = () => (still.matches ? requestAnimationFrame(draw) : kick());
    canvas.dataset.lit = "";
    kick();
  } catch (error) {
    // WebGPU unavailable or blocked: the static hero stays as it is.
    console.warn("Deploy light unavailable:", error);
  }
}

/** Accessible tabs; without JS every panel simply shows. */
export function mountTabs(root: HTMLElement) {
  const tabs = [...root.querySelectorAll<HTMLButtonElement>('[role="tab"]')];
  const panels = [...root.querySelectorAll<HTMLElement>('[role="tabpanel"]')];
  const select = (i: number, focus = false) => {
    tabs.forEach((t, j) => {
      t.setAttribute("aria-selected", String(i === j));
      t.tabIndex = i === j ? 0 : -1;
      panels[j].hidden = i !== j;
    });
    if (focus) tabs[i].focus();
  };
  tabs.forEach((t, i) => {
    t.addEventListener("click", () => select(i));
    t.addEventListener("keydown", (e) => {
      const step = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
      if (step) select((i + step + tabs.length) % tabs.length, true);
    });
  });
  select(0);
}

/** Copy buttons: `data-copy` holds the text; the label says "Copied" for a moment. */
export function mountCopy() {
  const status = document.querySelector("[data-copy-status]"); // the buttons' aria-labels hide "Copied", so say it here
  for (const button of document.querySelectorAll<HTMLButtonElement>("[data-copy]")) {
    const label = button.querySelector("[data-copy-label]");
    button.addEventListener("click", async () => {
      await navigator.clipboard.writeText(button.dataset.copy ?? "");
      if (status) status.textContent = "Copied to clipboard";
      setTimeout(() => status && (status.textContent = ""), 1400);
      if (!label) return;
      const original = label.textContent;
      label.textContent = "Copied";
      setTimeout(() => (label.textContent = original), 1400);
    });
  }
}
