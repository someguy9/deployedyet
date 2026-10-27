# Deployed Yet?

A free, open-source Mac menu bar app that answers one question: did it ship?

**[Download for macOS](https://github.com/someguy9/deployedyet/releases/latest/download/DeployedYet.dmg)** (macOS 14 or later) · [deployedyet.com](https://deployedyet.com)

- **Every account in one place.** Vercel, Cloudflare (Workers and Pages) and GitHub Actions, with as many accounts, teams and tokens as you have. Pick which projects to track.
- **The answer at a glance.** The menu bar shows `?` while something builds, `✓` when it's live and `!` when it broke. It's amber while building, green for a few minutes after a deploy lands, and red while something has failed. You can choose from six icon styles, or hide the icon until something needs a look.
- **What needs you comes first.** The menu lists failed deploys, then in-progress, then today, this week and earlier. Each row shows the branch, short commit and build time.
- **Notifications that matter.** Get told when a deploy fails or when production goes live, or click the bell on one build to hear when it finishes.
- **Easy on the APIs.** It checks every 5 seconds while something is building and every minute otherwise, backs off when rate limited, and refreshes when your Mac wakes.

## Tokens and privacy

Deployed Yet? only reads. Give each token the least access it needs:

| Provider | Token | Permissions |
| --- | --- | --- |
| Vercel | [Account token](https://vercel.com/account/tokens) | Vercel tokens can't be read-only yet, so scope each one to a single team and set an expiration. Add one token per team. |
| Cloudflare | [Custom API token](https://dash.cloudflare.com/profile/api-tokens) | Account Settings: Read, Workers Scripts: Read, Cloudflare Pages: Read |
| GitHub | [Fine-grained token](https://github.com/settings/personal-access-tokens/new) | Actions: Read and Metadata: Read, on the repos you deploy from |

- **Where tokens live:** in your Mac's Keychain, on this device only. They are never written to disk elsewhere, never logged, and only ever sent to `api.vercel.com`, `api.cloudflare.com` or `api.github.com` over HTTPS. Removing an account deletes its token.
- **Local cache:** project names, branches and commit messages are cached in `~/Library/Application Support/DeployedYet/` so the menu fills in instantly.
- **No tracking:** the app has no account, no analytics, no crash reporting and no server of its own.

## Build from source

You need Xcode and [Tuist](https://tuist.dev) (`brew install tuist`).

```bash
git clone https://github.com/someguy9/deployedyet
cd deployedyet
app/run-menubar.sh
```

The script generates the Xcode project, builds it, and launches the app, quitting any copy that's already running.

**Signing:** `app/Project.swift` signs with the maintainer's team, so set `DEVELOPMENT_TEAM` to your own team ID first (Xcode → Settings → Accounts). A stable signature also means Keychain doesn't ask for permission again after every rebuild.

**Releasing:** `app/release.sh` builds the universal app signed with Developer ID, makes the drag-to-Applications DMG, notarizes and staples it, and checks Gatekeeper (`--no-notarize` to try it without Apple's check).

## The website

`site/` is deployedyet.com: Astro and Tailwind, served as static files from a Cloudflare Worker.

Needs [Bun](https://bun.sh) (the exact version is pinned in `site/package.json`).

```bash
cd site
bun install
bun run dev       # http://localhost:4321
bun run deploy    # build + wrangler deploy
```

## Layout

```
app/    SwiftUI menu bar app (Tuist)
site/   deployedyet.com (Astro, Cloudflare Workers static assets)
```

## Contributing

Bug reports and ideas are welcome in [issues](https://github.com/someguy9/deployedyet/issues). Pull requests are welcome too; for anything big, open an issue first so we can agree on the approach.

If it saves you a few dashboard refreshes, you can [buy me a coffee](https://buymeacoffee.com/someguy).

## License

[MIT](LICENSE) © 2026 Andy Feliciotti
