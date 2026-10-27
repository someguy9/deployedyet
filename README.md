<p align="center">
  <img src="app/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" height="128" alt="Deployed Yet? app icon">
</p>

<h1 align="center">Deployed Yet?</h1>

<p align="center">A free, open-source Mac menu bar app that answers one question: did it ship?</p>

<p align="center">
  <a href="https://github.com/someguy9/deployedyet/releases/latest"><img src="https://img.shields.io/github/v/release/someguy9/deployedyet?label=release&color=3fb950" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-24292f?logo=apple&logoColor=white" alt="macOS 14 or later">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/someguy9/deployedyet?color=24292f" alt="MIT license"></a>
</p>

<p align="center">
  <a href="https://github.com/someguy9/deployedyet/releases/latest/download/DeployedYet.dmg"><b>Download for macOS</b></a> · <a href="https://deployedyet.com">deployedyet.com</a>
</p>

<p align="center">
  <img src="docs/menu.jpg" width="880" alt="The Deployed Yet? menu, open under its checkmark in the Mac menu bar: 'Yep. All deployed.' above six projects grouped into Today, This week and Earlier, each with its commit, branch and build time.">
</p>

- Add as many Vercel, Cloudflare (Workers and Pages) and GitHub Actions accounts as you have, then pick which projects to watch.
- The menu bar shows `?` while something is building, `✓` once it's live and `!` if it broke. It turns amber while building, green for a few minutes after a deploy lands, and red while anything is failing. There are six icon styles, and you can hide the icon until something needs you.
- Failed deploys sit at the top of the menu, then anything still building, then the rest by date. Each row shows the branch, short commit and build time.
- You can get a notification when a deploy fails or production goes live. Click the bell on a single build to hear when that one finishes.
- It checks every 5 seconds while something is building and once a minute otherwise. When it gets rate limited it backs off, and it catches up when your Mac wakes.

<p align="center">
  <img src="docs/settings.jpg" width="880" alt="Deployed Yet? Settings: an accounts sidebar and one Vercel team's projects, each with a toggle to track it.">
  <br><sub>Pick exactly which projects each account tracks.</sub>
</p>

<p align="center">
  <img src="docs/icon-styles.png" width="400" alt="The six menu bar icon styles, Plain, Circled, Filled, Triangle, Cloud and Dot, in their building, live and failed colors.">
  <br><sub>Six icon styles, in the menu's own colors.</sub>
</p>

## Tokens and privacy

The app only reads, so give each token the smallest set of permissions it'll accept:

| Provider | Token | Permissions |
| --- | --- | --- |
| Vercel | [Account token](https://vercel.com/account/tokens) | Vercel has no read-only tokens yet. Make one per team and give it an expiry date. |
| Cloudflare | [Custom API token](https://dash.cloudflare.com/profile/api-tokens) | Read on Account Settings, Workers Scripts and Cloudflare Pages |
| GitHub | [Fine-grained token](https://github.com/settings/personal-access-tokens/new) | Read on Actions and Metadata, for the repos you deploy from |

Tokens live in your Mac's Keychain, on this device only. They never get written anywhere else or logged, and they're only sent to `api.vercel.com`, `api.cloudflare.com` or `api.github.com` over HTTPS. Removing an account deletes its token.

To make the menu fill in instantly, the app caches project names, branches and commit messages in `~/Library/Application Support/DeployedYet/`. There's no account to sign up for, no analytics or crash reporting, and no server of mine involved.

## Build from source

You need Xcode and [Tuist](https://tuist.dev) (`brew install tuist`).

```bash
git clone https://github.com/someguy9/deployedyet
cd deployedyet
app/run-menubar.sh
```

That script generates the Xcode project, builds it and launches the app, quitting any copy that's already running first.

`app/Project.swift` signs with my team, so change `DEVELOPMENT_TEAM` to your own team ID before you build (it's in Xcode's Settings, under Accounts). Keeping the signature stable also stops Keychain from asking for permission after every rebuild.

To cut a release, run `app/release.sh`. It builds the universal app signed with Developer ID, packs it into the drag-to-Applications DMG, gets it notarized and stapled, and checks that Gatekeeper accepts it. The DMG lands in `app/build/release/`. Add `--no-notarize` to try everything except Apple's check.

## The website

`site/` is deployedyet.com: Astro and Tailwind, served as static files from a Cloudflare Worker.

You need [Bun](https://bun.sh). The exact version is pinned in `site/package.json`.

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

Bug reports and ideas go in [issues](https://github.com/someguy9/deployedyet/issues). Pull requests are welcome too, but for anything big, open an issue first so we can agree on the approach.

If it saves you a few dashboard refreshes, you can [buy me a coffee](https://buymeacoffee.com/someguy).

## License

[MIT](LICENSE) © 2026 Andy Feliciotti
