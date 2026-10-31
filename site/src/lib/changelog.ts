import { micromark } from "micromark";

export const RELEASES_API = "https://api.github.com/repos/someguy9/deployedyet/releases";
export const RELEASES_URL = "https://github.com/someguy9/deployedyet/releases";

type Release = { tag: string; date: string; body: string };

export function normalizeReleases(data: unknown): Release[] {
  if (!Array.isArray(data) || data.length > 100) throw new Error("Invalid releases response");
  const releases: Release[] = [];
  const tags = new Set<string>();
  for (const item of data) {
    if (!item || typeof item !== "object" || typeof item.draft !== "boolean" || typeof item.prerelease !== "boolean") throw new Error("Invalid release");
    if (item.draft || item.prerelease) continue;
    if (typeof item.tag_name !== "string" || !item.tag_name.trim() || typeof item.published_at !== "string" || !Number.isFinite(Date.parse(item.published_at)) || (item.body !== null && typeof item.body !== "string") || tags.has(item.tag_name)) throw new Error("Invalid release");
    tags.add(item.tag_name);
    releases.push({ tag: item.tag_name, date: item.published_at, body: item.body ?? "" });
  }
  if (!releases.length) throw new Error("No published stable releases");
  return releases.sort((first, second) => Date.parse(second.date) - Date.parse(first.date));
}

function escapeHtml(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

export function renderReleases(releases: Release[]): string {
  return releases.map(({ tag, date, body }) => {
    const encodedTag = encodeURIComponent(tag);
    const formattedDate = new Intl.DateTimeFormat("en-US", { year: "numeric", month: "long", day: "numeric", timeZone: "UTC" }).format(new Date(date));
    const notes = micromark(body).replace(/<img\b[^>]*>/g, "");
    return `<article class="release" id="${escapeHtml(tag)}"><header class="release-header"><div><time datetime="${escapeHtml(date)}">${formattedDate}</time><h2><a href="#${escapeHtml(encodedTag)}">${escapeHtml(tag)}</a></h2></div><a class="link-inline release-link" href="${RELEASES_URL}/tag/${escapeHtml(encodedTag)}">View on GitHub ↗</a></header><div class="release-notes">${notes || "<p>No release notes provided.</p>"}</div></article>`;
  }).join("");
}

export async function fetchReleases(): Promise<Release[]> {
  const response = await fetch(`${RELEASES_API}?per_page=100`, { credentials: "omit", signal: AbortSignal.timeout(8000), headers: { Accept: "application/vnd.github+json" } });
  if (!response.ok) throw new Error("Could not fetch releases");
  return normalizeReleases(await response.json());
}
