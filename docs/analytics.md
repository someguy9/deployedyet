# Usage analytics

The macOS app uses a small, typed PostHog HTTP capture client, not the SDK. No autocapture, session replay, person profiles, device fingerprinting, advertising IDs, crash reports, or dependency is added. Analytics is on by default for new and existing installations unless an explicit opt-out was previously saved. A dismissible settings notice explains collection and offers an immediate opt-out; collection may begin before dismissal. General → Privacy always exposes the preference and build status.

## Configure your project

The bundled production configuration targets the US PostHog project **701132** (`https://us.posthog.com/project/701132/home`). Debug analytics remains disabled.

1. Create/select a dedicated PostHog project for **Deployed Yet?**. Do not reuse a website project accidentally.
2. Edit `app/Resources/AnalyticsConfig.plist`:
   - `PostHogProjectToken`: the public project token beginning `phc_`, **not** a personal API key. This is shipped inside the app and is not a secret.
   - `PostHogHost`: `https://us.i.posthog.com` or `https://eu.i.posthog.com`, matching your project region. Other hosts, credentials, query strings, and paths are rejected. Self-hosted PostHog requires explicitly extending validation in `Analytics.Configuration`.
   - `AllowDebugAnalytics`: keep `false` for normal development. Set `true` only while testing against a separate test project; debug events carry `environment=development`.
3. Run `cd app && tuist generate --no-open`, then build using Xcode or the existing build scripts. Configuration is bundled at build time; changing it requires a rebuild/release.
4. Launch a configured Release build with **Share usage analytics** enabled by default. Confirm `analytics_session_started` appears in PostHog's live events, with no identifying payload fields. `analytics_enabled` is only emitted when collection is explicitly re-enabled.
5. Open the menu/settings, connect an account, and change a setting. Check the corresponding events. Disable analytics, repeat those actions, and confirm no new capture requests are made. Re-enable and confirm a new `distinct_id`.
6. Restore debug analytics to `false` before shipping and set the production project token. Release builds do not depend on the debug flag. Publish the updated website privacy policy alongside the app release.

The production capture token is configured and Release ingestion was verified on October 31, 2026. No personal API key is needed for ingestion. The additions below ship in app version 0.1.6 (build 7); the published 0.1.5 release is unchanged.

## Metrics that answer useful questions

The [Deployed Yet App Usage dashboard](https://us.posthog.com/project/701132/dashboard/2285886) contains verified native insights for engaged DAU, daily running installations, feature adoption, and release adoption. New 0.1.6 events become available after an analytics-enabled installation runs that build and performs the corresponding actions.

Always filter dashboards to `environment=production`. Unique IDs represent **analytics-enabled installations**, not all downloads or uniquely identifiable people. One person with two Macs can count twice; reinstalling/removing preferences or opting out and back in can create another identity. The opt-out rate cannot be measured as a percentage of all users using this client alone: opted-out users send nothing.

| Question | PostHog setup |
| --- | --- |
| How many people actively use the app? | Trend: `app_daily_active`, unique users, daily interval. Label **Engaged DAU (analytics-enabled installations)**. Triggered by actual menu/settings/feature interactions, not by polling. |
| How many installations keep it running? | Trend: `app_daily_running`, unique users, daily interval. Label **Daily running installations**. This includes unattended menu-bar usage; do not call it engaged DAU. |
| Are people coming back? | Retention: first `app_daily_active` → subsequent `app_daily_active`, daily and weekly. This starts at first observed analytics-enabled activity, not install date. |
| Are people completing setup? | Funnel: `account_connection_started` → `account_connected`, break down by `provider`. Use `account_connection_failed` for failures. These are attempts while analytics is enabled only; earlier setup is not backfilled. |
| How many tracked projects do users have? | `app_daily_snapshot`, break down by `tracked_project_count_bucket`; filter `account_count_bucket` as needed. Snapshot reflects the first successful sample that day, not continuous state. |
| Which features matter? | Trends: `deployment_opened`, `deployment_watch_changed`, `project_tracking_changed`, `setting_changed`; break down by `setting` and `enabled`. |

Daily events use UTC date markers, persisted only after an HTTP 2xx response. Use UTC for strict calendar-day comparisons in PostHog. Each meaningful interaction checks the active marker, so an app running across midnight does not depend on restarting to count active use. A lightweight one-minute timer checks running/snapshot markers, with a wake check and no heartbeat while system sleep is observed. The timer is not an event per minute: normally only three daily events per active installation are delivered. A window left open overnight alone does not establish engaged activity the next day.

## Event catalog

All events include `app_version`, `app_build`, `macos_major_version`, `schema_version=1`, and `environment`. Capture envelopes include event timestamp and the random installation `distinct_id`. `$process_person_profile=false` disables person profile creation, `$geoip_disable=true` disables GeoIP enrichment, and `$ip=0.0.0.0` suppresses the real IP in event properties. Network infrastructure still receives the connection's source IP.

| Event | When | Additional properties |
| --- | --- | --- |
| `analytics_enabled` | User re-enables collection after opting out | None |
| `analytics_session_started` | Analytics-enabled, configured client starts or resumes after enabling | None |
| `app_daily_running` | Awake app starts, wakes, or crosses a UTC day | None |
| `app_daily_active` | First interaction on a UTC day, including re-enabling analytics | None |
| `app_daily_snapshot` | First daily sample of local setup | `account_count_bucket`, `tracked_project_count_bucket`: `0`, `1`, `2–5`, `6–10`, `11+` |
| `menu_opened` | Menu panel opens | None |
| `settings_opened` | Settings is requested, including initial setup | None |
| `account_connection_started` | User submits a connection attempt | `provider`: `vercel`, `cloudflare`, `github` |
| `account_connected` | Token validated and stored successfully | `provider` |
| `account_connection_failed` | Connection attempt fails | `provider`; never an error message/status body |
| `account_removed` | User removes an account | `provider` |
| `project_tracking_changed` | User selects/deselects projects individually or in bulk | None; automatic discovery does not emit this event |
| `setting_changed` | User changes an instrumented boolean preference | `setting`, `enabled` |
| `deployment_opened` | User opens a deployment row or its site/project link | None; never the destination URL |
| `deployment_watch_changed` | User toggles a deployment's notification bell | `enabled` |
| `refresh_requested` | User manually refreshes | None; automatic polls do not emit it |
| `project_filter_used` | User starts a nonempty filter (0.1.6+) | None; no query text, length, result contents, or per-keystroke events. Clearing and starting another filter emits again. |
| `project_group_toggled` | User expands/collapses one group or all groups (0.1.6+) | `expanded`, `scope`: `single` or `all`; no group identity |
| `projects_bulk_selected` | User selects/deselects a group's matching projects (0.1.6+) | `selected`, `filtered`, `project_count_bucket`: same buckets as daily snapshot; also retains `project_tracking_changed` for compatibility |
| `update_check_requested` | User manually checks for updates (0.1.6+) | None; scheduled checks do not emit it |

Instrumented settings: preview tracking, failed/ready notifications, push watching, icon animation, icon-only-when-busy, per-project production-only, launch-at-login (only after registration succeeds), and automatic updates (0.1.6+, user changes only, not restored startup preferences). Appearance choice values, token errors, notification delivery, automatic provider requests, and git activity are deliberately not captured.

Use the new events to evaluate whether large project lists need better navigation, whether bulk selection is useful, and whether update controls are discoverable. All additions originate in explicit user actions and therefore qualify for engaged DAU. They do not add background polling or change opt-out behavior.

### Turn signals into product decisions

| Product question | Signal to review | Possible follow-up |
| --- | --- | --- |
| Do installations keep getting value? | Engaged DAU and return activity on later days, separately from daily running | Investigate onboarding and recurring value, not just launch counts |
| Are project lists cumbersome? | Unique installations using filters, collapse controls, and filtered bulk selection | Improve navigation; usage alone does not prove friction |
| Is bulk selection worth improving? | Unique installations using bulk selection, split by selected/filtered and count bucket | Prioritize large-list workflows without identifying projects |
| Are update controls useful? | Manual update checks, automatic-update preference changes, and version adoption | Improve update discoverability; a check is not a successful install |

Compare adoption only across versions that emit the relevant events. Prefer unique installations over raw click totals, use consistent time windows, and combine these signals with user feedback before deciding what to build. These are derived, noncanonical metrics; anonymous installations are not verified people, and opted-out usage is absent.

## Delivery and privacy boundaries

- Nothing is sent and no analytics identifier is generated without analytics enabled, valid configuration, and an allowed build environment.
- The payload API accepts typed events only. New properties must be deliberately added and reviewed; never pass model objects, URLs, free-form strings, tokens, account/project/deploy IDs, or error descriptions.
- Events are serialized through an ephemeral cookie-free, credential-free, cache-free URL session. Redirects are rejected, so project tokens and payloads cannot follow an unexpected redirect.
- The in-memory queue is bounded to 50 waiting events, with one request in flight and short timeouts. There is no disk queue or payload logging. Events are best-effort: offline failures and process exits can lose them. Daily failures are retried on a later check/interaction after a five-minute cooldown; ordinary events are not retried.
- Opt-out cancels the timer and current URL session, clears pending events, daily markers, and the installation identifier. An already-received request cannot be recalled. Old asynchronous completions cannot write markers or drain a new opt-in session.
- Ambiguous network failures can cause daily event duplicates. Use unique users, not total event count, for DAU. No delivery guarantee is implied by a successful capture endpoint response.
- Use PostHog project retention/access controls for stored data. There is no in-app server-side deletion feature; the toggle only controls future collection and local identity.

API reference: https://posthog.com/docs/api/capture

Profile behavior: https://posthog.com/docs/data/anonymous-vs-identified-events
