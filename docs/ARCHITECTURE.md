# Architecture

## Components

```
plugin/                 DSH bundle (Host + Client)
menu-bar/               native macOS menu-bar app (SwiftUI)
  Host/                 MenuBarExtra, loopback server, refresh request
  Shared/               snapshot models and formatting
  Widget/               experimental WidgetKit extension
```

The plugin is the only component that talks to providers. The menu-bar app is a
local reader with a native UI; it never holds provider credentials.

## Host half (`plugin/index.js`, `plugin/lib/`)

### Discovery

`lib/accounts.js` resolves accounts from local sources; credentials stay in
process memory.

| Provider | Sources |
|---|---|
| Codex | `$CODEX_HOME/auth.json` (default `~/.codex`), additional `~/.codex-*/auth.json`, CC Switch `providers` rows (`app_type = 'codex'`), manual config |
| Claude | macOS Keychain `Claude Code-credentials`, `~/.claude/.credentials.json`, `CLAUDE_CODE_OAUTH_TOKEN`, manual config |
| Grok | every entry in `~/.grok/auth.json` with a `key`, manual config |

Codex identity is derived from the access-token JWT: `chatgpt_user_id` (falling
back to email) is the account key, while `chatgpt_account_id` is the team id
sent in the `chatgpt-account-id` header. This allows two users in one ChatGPT
team to appear as two accounts. Expired CC Switch tokens are skipped; the CLI
account wins when both describe the same user. Claude refresh tokens are read
from the Keychain only when a refresh is due, and the rotated tokens are written
back to the same item (see “Claude token refresh” below).

### Adapters (`lib/providers.js`)

All adapters are `GET` requests with a 12 s timeout. HTTP 401/403 maps to
`auth`, 429 to `rate-limit`, timeouts to `timeout`, and other failures to
`http`/`network`/`parse`.

| Provider | Request | Normalization |
|---|---|---|
| Codex | `https://chatgpt.com/backend-api/wham/usage` | `rate_limit.primary_window` / `secondary_window`; `used_percent`, `limit_window_seconds`, `reset_at` or `reset_after_seconds`; plan, credits, spend control |
| Claude | `https://api.anthropic.com/api/oauth/usage` (`anthropic-beta: oauth-2025-04-20`) | `five_hour`, `seven_day`, `seven_day_opus`, `seven_day_sonnet`, optional `extra_usage`; `utilization` is 0–100; ISO reset |
| Grok | `https://cli-chat-proxy.grok.com/v1/billing?format=credits` (`x-grok-client-mode: cli`) | weekly `creditUsagePercent` (missing on a fresh period means 0), period start/end, `productUsage`, prepaid/on-demand |

A normalized window is:

```js
{ key, label, usedPercent, remainingPercent, windowSeconds, resetsAt, exhausted }
```

### Claude token refresh

`ensureClaudeToken()` runs before each Claude fetch and once more on a 401:

1. Skip when the access token is more than two minutes from expiry.
2. Re-read the Keychain first; if Claude Code refreshed it concurrently and the
   token is valid, adopt that token.
3. Otherwise `POST https://platform.claude.com/v1/oauth/token` with
   `grant_type=refresh_token`, the Keychain refresh token, and the Claude Code
   client id.
4. Write the new access/refresh tokens and expiries back to the same Keychain
   item, preserving `mcpOAuth`.
5. Retry the usage request.

`claudeRefreshTokens: false` disables steps 3–4. Tokens are never persisted in
the plugin state or returned over HTTP.

### Scheduler and refresh requests

- Initial collection 1.2 s after activation.
- A 30 s ticker calls `collect()` when `state.updatedAt` is at least
  `pollSeconds` old (default 300 s).
- Each account has a `refreshMinSeconds` floor (default 120 s); a forced
  refresh bypasses it.
- `refresh.request` next to the state file is watched every 2 s by the Host and
  triggers `collect({ force: true })`, at most once per 8 s. This is how the
  macOS helper requests a real provider refresh without browser authentication.

### State and events (`lib/store.js`)

`$DSH_HOME/usage-monitor/state.json` (mode 0600) contains:

```json
{
  "version": 1,
  "updatedAt": "ISO",
  "accounts": { "<id>": { "...snapshot..." } },
  "events": [],
  "notified": [],
  "diag": {}
}
```

Accounts are stored as an id-keyed object; the HTTP API and helper expose the
array form. Snapshots hold labels, emails, plans, windows, product breakdowns and
sanitized errors. No tokens.

Reset detection compares the previous and new snapshot for a window:

- reset: reset timestamp moved forward by at least a quarter window (or 60 s)
  and used percent dropped;
- refill: used percent dropped at least 3 points without a reset;
- low: remaining percent crossed `lowThreshold` once per window.

Events are capped at 50 and deduplicated by id; native notifications use
`notified` so they are not repeated.

### HTTP routes

Registered through `ctx.connection.fetch.register`, so the `/api` bridge enforces
browser trust and cookie authentication before the handler runs:

| Route | Purpose |
|---|---|
| `GET /api/usage-monitor/state` | cached snapshot, recent events, `diag`, `ui`; triggers a background refresh when stale |
| `POST /api/usage-monitor/refresh` | force refresh, optional `{ "accountId": "..." }` |

When `connection` is unavailable the plugin still runs (for the tool and
scheduler) but exposes no routes.

### Tool

`usage_status` is registered on the Host tools service. It filters by provider
or account substring, returns JSON, and renders a compact text report. It reads
the same snapshot as the UI.

## Client half (`plugin/client.js`)

`window.__ModuleLoader__.load` registers a lazy factory with `inject: ['slots',
'locale']`. `apply(ctx)`:

- registers English and Traditional Chinese dictionaries under `usage-monitor`;
- creates a shared store and starts a 30 s ticker that calls `/state` every
  second tick (60 s) while the page is visible, plus on visibility changes;
- registers `main`, `sidebar.panellist`, `sidebar.footer.action`,
  `conversation.composer.dock`, and `shell.overlay` occupants;
- uses `useSyncExternalStore` for panel, icon, dock strip and toasts.

The page receives only the snapshot; it never sees a credential.

## Menu-bar app (`menu-bar/Host/`)

- `MenuBarExtra` with `.window` style; `LSUIElement` keeps it out of the Dock.
- `HostModel` reads `$DSH_HOME/usage-monitor/state.json` on launch and when
  `StateServer` notices a modification (10 s poll), decoding accounts as an
  array.
- `StateServer` is a loopback-only `NWListener` on `127.0.0.1:47821` with a
  static token; it returns the snapshot JSON and reloads WidgetKit timelines.
- The menu-bar label shows the worst window of **Worst of all** (the provider
  driving the number) or of the selected provider. The provider mark is rendered
  from a bundled template logo into a colored `NSImage`.
- The **Refresh** button writes `refresh.request` next to the state file, then
  polls the state for up to 20 s. It cannot call the browser-authenticated
  `/api` bridge; the request file is the bridge.
- `MenuBarSelection` is persisted in `UserDefaults`.
- The popover groups accounts by provider, with brand marks, provider colors,
  window bars, reset times and relative countdowns.

The WidgetKit extension is included but experimental: macOS `chronod` rejects
widgets from ad-hoc-signed apps. Signing with a developer identity is required
to use it. The menu-bar surface does not need signing.

## Failure behavior

- A provider failure keeps the last known windows on the card, marks the account
  `auth` or `error`, and stores a sanitized detail.
- Missing credentials produce a “not signed in” placeholder (Claude) or no card
  for that provider.
- Stale snapshots are retained; the helper shows STALE after 15 minutes, the
  in-app card after 10 minutes.
- Provider endpoints are undocumented and can change; adapters are isolated so a
  single endpoint failure does not break the others.

## Development

Plugin syntax: `node --check` on every file. The plugin is linked into a profile
by Plugin Manager; Host code changes need the bundle to be reloaded (toggle the
plugin row or restart DSH), while Client code hot-reloads in the open page.

Menu-bar build:

```bash
cd menu-bar
xcodegen generate
xcodebuild -project UsageWidget.xcodeproj -scheme UsageWidgetHost \
  -configuration Release -derivedDataPath /tmp/UsageWidgetDerived build
```

Build under `/tmp` to avoid file-provider xattrs breaking codesign.
