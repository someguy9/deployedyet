# Deployed Yet?

A Mac menu bar app (`app/`, Tuist + SwiftUI) and its website (`site/`, Astro on a Cloudflare Worker, deployedyet.com).

## Keep the website in step with the app

The site shows the app as HTML rebuilt from the Swift views, not screenshots, so it goes stale unless it's updated alongside the app.

When a change alters what the app shows or how it works, update the site in the same change:

- `site/src/components/MenuMock.astro` mirrors `app/Sources/MenuView.swift` (header, filters, sections, rows, footer).
- `site/src/components/SettingsMock.astro` mirrors `app/Sources/SettingsView.swift` (sidebar, account pane, project groups).
- `site/src/lib/site.ts` and `site/src/pages/index.astro` hold the provider token permissions, what each provider tracks, features, the tour list and the FAQ. A new token permission also goes in the app's hint (`Provider` in `app/Sources/Models.swift`) and the README table.
- `site/src/pages/privacy.astro` covers anything that changes what leaves the Mac.

Match the app's real strings, sizes in points and order. When you can't tell if the site needs a change, check: does the mock or copy still describe the app as it now is?

## Releasing

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `app/Project.swift`. Sparkle compares `CFBundleVersion`, so it must go up every release.
2. Commit to `main` and push.
3. Run `app/release.sh`. It builds, signs, notarizes and staples the DMG and writes the appcast.
4. Publish with the `gh release create` command the script prints, using written notes (`--notes-file`) with a full commit SHA for `--target`.
5. Add the release to `site/src/lib/releases-snapshot.json`, commit, push, and deploy the site: `bun run --cwd site deploy`. The deploy also refreshes the version shown on the homepage.

Don't commit or push unless asked.
