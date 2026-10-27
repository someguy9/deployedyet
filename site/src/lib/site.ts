// Single source for what the page says. Keep in step with what the app actually does.

export const SITE = "https://deployedyet.com";
// The DMG keeps one name every release (app/release.sh), so this always downloads the newest version.
export const DOWNLOAD_URL = "https://github.com/someguy9/deployedyet/releases/latest/download/DeployedYet.dmg";
export const REPO_URL = "https://github.com/someguy9/deployedyet";
export const COFFEE_URL = "https://buymeacoffee.com/someguy";

export type Provider = {
  id: "vercel" | "cloudflare" | "githubactions";
  name: string;
  tint: string;
  tracks: string;
  token: string;
  tokenUrl: string;
};

export const providers: Provider[] = [
  {
    id: "vercel",
    name: "Vercel",
    tint: "currentColor",
    tracks: "Production and preview deploys for every team, with branch, commit and build time.",
    token: "Create a token scoped to one team with an expiration. Vercel tokens can’t be read-only yet; the app only ever reads.",
    tokenUrl: "https://vercel.com/account/tokens",
  },
  {
    id: "cloudflare",
    name: "Cloudflare",
    tint: "#F38020",
    tracks: "Workers and Pages across every account. wrangler deploys show up as “just shipped”.",
    token: "A custom token with Account Settings, Workers Scripts and Cloudflare Pages, all Read.",
    tokenUrl: "https://dash.cloudflare.com/profile/api-tokens",
  },
  {
    id: "githubactions",
    name: "GitHub Actions",
    tint: "#2088FF",
    tracks: "Workflow runs grouped by commit, so CI + Deploy on one push is one row. Cron and bot runs are ignored.",
    token: "A fine-grained token with Actions and Metadata, both Read, on the repos you deploy from.",
    tokenUrl: "https://github.com/settings/personal-access-tokens/new",
  },
];

export type Feature = { title: string; body: string; tag: string };

/** The bento grid. First item is the big one. */
export const features: Feature[] = [
  {
    tag: "The answer",
    title: "? while it builds. ✓ when it ships. ! when it breaks.",
    body: "The menu bar icon answers the question in the name. It wobbles while anything builds and morphs into the answer when it lands.",
  },
  {
    tag: "Details",
    title: "Watch one build.",
    body: "Building rows count up live. Click the bell on one and you hear about it the second it finishes, whatever your other settings.",
  },
  {
    tag: "Focus",
    title: "Previews, or production only.",
    body: "Track preview builds by default, or right-click a busy repo and keep it to production.",
  },
  {
    tag: "Quiet",
    title: "Hides until it matters.",
    body: "Optionally show the icon only while something is building or broken. Out of the way the rest of the time.",
  },
  {
    tag: "Private",
    title: "No server. No account.",
    body: "Tokens live in your Mac’s Keychain and only go to each provider’s own API. The code is open source, so you can check.",
  },
  {
    tag: "Polite",
    title: "Fast without hammering APIs.",
    body: "Polls every 5s only while something builds, backs off when rate limited, refreshes after your Mac wakes.",
  },
];

export const faqs: { q: string; a: string }[] = [
  {
    q: "Is it free?",
    a: "Yes. Free and open source under the MIT license. If it saves you some dashboard refreshing, you can buy me a coffee.",
  },
  {
    q: "Which Macs does it run on?",
    a: "macOS 14 Sonoma or later.",
  },
  {
    q: "Where do my tokens go?",
    a: "Into your Mac’s Keychain, and nowhere else. The app talks directly to api.vercel.com, api.cloudflare.com and api.github.com. There’s no Deployed Yet? server, and no analytics in the app.",
  },
  {
    q: "Why does Vercel need a full-access token?",
    a: "Vercel tokens can only be narrowed to a team or project, not made read-only. Scope yours to one team and give it an expiration. Read-only “Sign in with Vercel” is coming once Vercel opens it up.",
  },
  {
    q: "Why do some Workers say “deployed” but never “building”?",
    a: "A plain wrangler deploy has no build phase Cloudflare can report. Those Workers show when they shipped, with a “just shipped” flash for the first two minutes.",
  },
  {
    q: "I hid the icon. How do I get back to Settings?",
    a: "Open Deployed Yet? again from Spotlight or Finder. Settings opens right up.",
  },
];
