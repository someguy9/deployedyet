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
    tracks: "Production and preview deploys for each team, with the branch, commit and how long the build took.",
    token: "Make one per team and give it an expiry date. Vercel doesn’t do read-only tokens yet, but the app never writes anything.",
    tokenUrl: "https://vercel.com/account/tokens",
  },
  {
    id: "cloudflare",
    name: "Cloudflare",
    tint: "#F38020",
    tracks: "Workers, Workers Builds and Pages on every account the token can see. A git build shows while it runs; a plain wrangler deploy shows up as “just shipped”, since there’s no build to watch.",
    token: "A custom token with Read access to Account Settings, Workers Scripts, Workers Builds Configuration and Cloudflare Pages.",
    tokenUrl: "https://dash.cloudflare.com/profile/api-tokens",
  },
  {
    id: "githubactions",
    name: "GitHub Actions",
    tint: "#2088FF",
    tracks: "Runs are grouped by commit, so your CI and deploy workflows from one push show up as one row. Cron jobs and bot runs don’t count.",
    token: "A fine-grained token with Read access to Actions and Metadata on the repos you deploy from.",
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
    tag: "Find",
    title: "Find the deployment you need",
    body: "Search tracked rows by project, team, account, branch, commit, message or provider. Combine provider and state filters, see the matching count, and clear them whenever you like.",
  },
  {
    tag: "Details",
    title: "Keep an eye on one build",
    body: "Building rows show a live timer. Click the bell on one and you’ll get a notification when it’s done, even if you’ve turned the others off.",
  },
  {
    tag: "Focus",
    title: "Skip the preview noise",
    body: "Previews are tracked by default. If one repo builds previews all day, right-click it and keep it to production.",
  },
  {
    tag: "Quiet",
    title: "Hide it when nothing’s happening",
    body: "Set the icon to show up only while something is building or broken, and it stays out of your menu bar otherwise.",
  },
  {
    tag: "Private",
    title: "Your tokens stay on your Mac",
    body: "They’re stored in the Keychain and only ever sent to Vercel, Cloudflare or GitHub. There’s no server of mine in the middle, and you can read the code to check.",
  },
  {
    tag: "Polite",
    title: "Easy on your API limits",
    body: "It checks every 5 seconds while something’s building and once a minute otherwise. If it gets rate limited it backs off, and it catches up when your Mac wakes.",
  },
];

export const faqs: { q: string; a: string }[] = [
  {
    q: "Is it free?",
    a: "Yes, and the code is MIT licensed. If it saves you a few dashboard refreshes, you can buy me a coffee.",
  },
  {
    q: "Which Macs does it run on?",
    a: "Any Mac on macOS 14 Sonoma or later, Apple Silicon or Intel.",
  },
  {
    q: "Where do my tokens go?",
    a: "Into your Mac’s Keychain. The app sends each one only to its own provider (api.vercel.com, api.cloudflare.com or api.github.com), and there’s no Deployed Yet? server in between. Optional usage analytics never includes a token or anything about your deploys.",
  },
  {
    q: "Why does Vercel need a full-access token?",
    a: "Vercel lets you limit a token to one team or project, but it has no read-only option yet. Scope yours to a single team and set an expiry date. If Vercel ever adds read-only access, I’ll switch to it.",
  },
  {
    q: "Why do some Workers say “deployed” but never “building”?",
    a: "When you run wrangler deploy yourself, there’s no build for Cloudflare to report, so the app only sees when it went live. Those Workers say “just shipped” for the first two minutes instead. Workers that build from git (Workers Builds) do show “building”, as long as your token has Read access to Workers Builds Configuration.",
  },
  {
    q: "I hid the icon. How do I get back to Settings?",
    a: "Open Deployed Yet? again from Spotlight or Finder and Settings pops up.",
  },
];
