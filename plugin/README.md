# Usage Monitor

One panel for the remaining Codex, Claude and Grok quota on every account,
with reset countdowns and reminders when a window resets or refills.

## What it shows

- Sidebar gauge icon → **Usage Monitor** page.
- One card per account: email label, plan, live/stale state.
- One row per quota window: remaining bar, `% left`, `% used`, reset countdown
  and absolute reset time.
- Multiple Codex accounts, even when they share a ChatGPT team account id.
- Claude session, weekly, Opus/Sonnet and extra-usage windows when Claude Code
  is signed in officially.
- Grok product breakdown (Grok Build / Chat) and prepaid/on-demand balance.
- Codex credits and spend-control warnings when the API returns them.
- A compact strip under the composer with the three tightest windows.
- A toast when a window resets or refills, plus one low-quota warning per
  window. Native macOS notifications are opt-in.
- The `usage_status` tool lets the model answer "which account has quota left?"

## Where the numbers come from

Everything is read locally, on this machine, and only the provider's own usage
endpoint receives the credential:

| Provider | Credential (read-only) | Endpoint |
|---|---|---|
| Codex | `~/.codex/auth.json` plus `~/.codex-*/auth.json` and CC Switch rows | `GET https://chatgpt.com/backend-api/wham/usage` |
| Claude | Claude Code OAuth: macOS Keychain `Claude Code-credentials`, `~/.claude/.credentials.json`, or `CLAUDE_CODE_OAUTH_TOKEN` | `GET https://api.anthropic.com/api/oauth/usage` |
| Grok | `~/.grok/auth.json` (every account entry; `key`, `email`) | `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` |
| Codex extras | CC Switch `~/.cc-switch/cc-switch.db`, `providers` rows with `app_type = 'codex'` | the same Codex endpoint |
| Manual | `tokenEnv` or `tokenFile` in the plugin config | the provider's endpoint |

CC Switch is read with `sqlite3 -readonly`. Codex rows are deduplicated by the
**JWT user id** (falling back to email), not the stored team `account_id`: two
people in one ChatGPT team share that id but have separate usage. Expired CC
Switch tokens are skipped; the CLI account wins when both describe one user.

Claude quota is only available for an official Claude Code OAuth login. A third-party
relay/API-key setup has no usage endpoint, so Claude shows a **not signed in**
card until you run `claude` and use `/login` with the
subscription account. The token is then picked up from the Keychain.

The Claude Code access token lasts about eight hours. When it is within two
minutes of expiry — or a request returns 401 — the plugin exchanges the Keychain
refresh token at `platform.claude.com/v1/oauth/token`, then writes the new
access and rotated refresh tokens back to `Claude Code-credentials`. No daily
re-login is needed until the **refresh token** expires (about 27 days) or is
revoked. Set `claudeRefreshTokens: false` to keep the plugin read-only.

## Privacy

- Credentials are read into process memory only. They are never written to the
  plugin state, never returned by an HTTP route, and never logged.
- The snapshot at `$DSH_HOME/usage-monitor/state.json` (mode 0600) contains account
  labels, emails, percentages, reset times, and sanitized error text. No tokens.
- The browser receives numbers and labels over the existing authenticated
  `/api` bridge; the page never sees a credential.
- Codex and Grok credentials are never refreshed or rewritten. Claude Code's
  Keychain credential is refreshed automatically before expiry (or after a
  401); the rotated access/refresh tokens are written back to the same Keychain
  item so Claude Code stays in sync. Tokens never enter the plugin state,
  routes, or logs.

## Config

Add an override row to `$DSH_HOME/profiles/<profile>/cordis.patch.yml`. The row
already exists in the bundle's own patch, so this is an id-targeted override;
`config` is replaced wholesale, so restate every field you want to keep:

```yaml
- id: usage-monitor
  name: '@local/usage-monitor'
  config:
    pollSeconds: 300          # background refresh cadence
    refreshMinSeconds: 120    # per-account minimum gap between reads
    notifications:
      toast: true             # in-app toasts
      macos: true             # native macOS notifications
      lowThreshold: 10        # warn once when a window drops to/below this %
    discovery:
      cli: true               # Codex + Grok CLI credential stores
      ccSwitch: true          # CC Switch DB (read-only)
    claudeRefreshTokens: true # auto-refresh Claude Code OAuth from Keychain
    ui:
      dock: true              # strip under the composer
    accounts:                 # optional manual accounts
      - id: codex-work
        provider: codex
        label: Codex · work
        tokenFile: ~/.secrets/codex-work.token
      - id: grok-team
        provider: grok
        label: Grok · team
        tokenEnv: GROK_TEAM_TOKEN
      - id: claude-work
        provider: claude
        label: Claude · work
        tokenFile: ~/.secrets/claude-work.token
```

A token file may be a raw token or any of the JSON shapes the CLIs use
(`.key`, `.tokens.access_token`, `.claudeAiOauth.accessToken`, or an entry with
`key`).

## Routes

| Route | Purpose |
|---|---|
| `GET /api/usage-monitor/state` | cached snapshot + recent events; triggers a refresh when stale |
| `POST /api/usage-monitor/refresh` | force refresh, optional `{ "accountId": "..." }` |

Both are served through `ctx.connection.fetch.register`, so the existing
browser-trust and cookie checks answer 401/403 before the handler runs.

## Troubleshooting

- **"Sign in again"** — run `codex login`, `grok login`, or `claude` → `/login`.
  Codex/Grok credentials are never refreshed by the plugin; Claude is refreshed
  automatically unless `claudeRefreshTokens` is disabled.
- **Only one Codex account** — a second account needs a different JWT user.
  Log in with another ChatGPT account (a separate `CODEX_HOME`, e.g.
  `CODEX_HOME=~/.codex-work codex login`, is picked up automatically), or add a
  manual `tokenFile` entry.
- **Claude says "not signed in"** — only an official Claude Code OAuth login has
  a quota endpoint; a relay `ANTHROPIC_AUTH_TOKEN` does not.
- **Claude shows HTTP 401** — the access token could not be refreshed (refresh
  token expired/revoked, or Keychain write failed). Re-run `claude` → `/login`.
- **Grok card missing** — `~/.grok/auth.json` must have an entry with `key`.
- **Stale badge** — the provider endpoint failed or the Host is offline; the
  last good numbers are kept and the next poll retries.
- **Toast did not appear** — events are only emitted for a real transition after
  the plugin has seen the window at least once; a fresh install never toasts.

## Known limits

- Provider usage endpoints are not documented public APIs and can change.
- Codex/Grok tokens expire; the plugin reports it instead of rotating those
  CLI credentials.
- Claude auto-refresh needs a valid refresh token; after ~27 days or a logout
  you must sign in to Claude Code again.
- Claude requires an official Claude Code OAuth login; the relay/API-key path
  has no quota endpoint.
- The panel's visual result is verified through slot registration and live
  state, not a screenshot.
