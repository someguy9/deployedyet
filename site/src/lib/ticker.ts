import { setLightState, type DeployState } from "~/lib/light";

// The hero's deploy ticker: one card per provider, each going building -> live (or failed), on a loop.
// Built on Emil Kowalski's rules: state changes are CSS transitions (interruptible), text swaps blur
// through, nothing scales from zero, the progress bar is linear, and the loop pauses on hover and
// while the tab is hidden. Reduced motion keeps the story with opacity only (handled in CSS).

const SPEED = 9; // demo seconds per real second, so a 31s build plays in about 3.4s
const HOLD_MS = 2600;

export function mountTicker(root: HTMLElement) {
  const cards = [...root.querySelectorAll<HTMLElement>("[data-deploy]")];
  if (!cards.length) return;
  document.documentElement.classList.add("js"); // switch the static list into the animated stack
  let index = 0;
  let paused = false;
  let timer = 0;
  let clock = 0;
  let phaseStart = 0;
  let elapsedBeforePause = 0;

  const label = (card: HTMLElement) => card.querySelector<HTMLElement>("[data-elapsed]");

  function show(i: number) {
    index = i;
    const before = (i - 1 + cards.length) % cards.length;
    cards.forEach((card, j) => {
      // The leaving card drifts up, the rest wait below: one direction, so the motion reads as a feed.
      card.dataset.pos = j === i ? "active" : j === before ? "before" : "after";
      card.setAttribute("aria-hidden", String(j !== i));
    });
    const card = cards[i];
    // Each card builds for its own stated time, so the clock lands on the number the card then shows.
    const ms = ((Number(card.dataset.seconds) || 30) / SPEED) * 1000;
    card.style.setProperty("--build", `${ms}ms`);
    card.dataset.state = "building";
    setLightState("building");
    startClock(card);
    schedule(ms, finish);
  }

  function finish() {
    const card = cards[index];
    const end = (card.dataset.end ?? "live") as DeployState;
    stopClock();
    const el = label(card);
    if (el) el.textContent = clockText(Number(card.dataset.seconds) || 30); // land exactly, not a tick short
    card.dataset.state = end;
    setLightState(end);
    schedule(HOLD_MS, () => {
      // Reset the finished card quietly once it is out of view.
      const leaving = card;
      setTimeout(() => {
        leaving.dataset.state = "building";
      }, 400);
      show((index + 1) % cards.length);
    });
  }

  // The visible timer counts up while building ("Building 0:14"), a demo of the app's live timer.
  function startClock(card: HTMLElement) {
    stopClock();
    const el = label(card);
    const begin = performance.now();
    const tick = () => {
      if (paused) return;
      const seconds = Math.floor(((performance.now() - begin) / 1000) * SPEED);
      if (el) el.textContent = clockText(seconds);
    };
    tick();
    clock = window.setInterval(tick, 120);
  }
  function stopClock() {
    clearInterval(clock);
  }
  const clockText = (seconds: number) => `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;

  function schedule(ms: number, fn: () => void) {
    clearTimeout(timer);
    phaseStart = performance.now();
    elapsedBeforePause = 0;
    pending = { ms, fn };
    if (!paused) timer = window.setTimeout(fn, ms);
  }
  let pending: { ms: number; fn: () => void } | undefined;

  function pause() {
    if (paused) return;
    paused = true;
    clearTimeout(timer);
    elapsedBeforePause += performance.now() - phaseStart;
    root.dataset.paused = "";
  }
  function resume() {
    if (!paused) return;
    paused = false;
    delete root.dataset.paused;
    if (!pending) return;
    phaseStart = performance.now();
    timer = window.setTimeout(pending.fn, Math.max(0, pending.ms - elapsedBeforePause));
  }

  root.addEventListener("pointerenter", pause);
  root.addEventListener("pointerleave", resume);
  root.addEventListener("focusin", pause);
  root.addEventListener("focusout", resume);
  document.addEventListener("visibilitychange", () => (document.hidden ? pause() : resume()));

  show(0);
}
