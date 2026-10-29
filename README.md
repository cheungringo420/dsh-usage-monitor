# DSH Usage Monitor

A quota dashboard for **DeepSeek Harness** with a native macOS menu-bar
companion. It shows how much of each Codex, Claude and Grok subscription window
is left, when every window resets, and reminds you when a window resets or
refills.

Two pieces work together:

- **`plugin/`** — a DeepSeek Harness bundle that discovers local accounts, reads
  the providers’ usage endpoints every five minutes, and renders a sidebar
  panel, composer strip, toasts, and a `usage_status` agent tool.
- **`menu-bar/`** — a small native macOS app that shows the tightest window in
  the menu bar and a polished popover with every account. It reads the plugin’s
  local snapshot and can ask the plugin to refresh on demand.

The monitor is **read-only towards the providers**: it calls usage/billing
metadata endpoints, never a model endpoint, so it does not consume inference
tokens or subscription quota.

---

## Features

- Every local account in one place: Codex (including several users that share a
  ChatGPT team account id), Claude Code, and Grok.
- 5-hour / weekly / Opus / Sonnet / extra-usage windows with remaining
  percentage, used percentage, absolute reset time, and a live countdown.
- Grok product breakdown (Grok Build / Chat), prepaid and on-demand balance.
- Reset and refill detection with in-app toasts and optional native macOS
  notifications.
- Multiple Codex accounts, even when CC Switch stores copies of the same
  ChatGPT account.
- Claude Code OAuth automatic refresh from the macOS Keychain, with write-back,
  so Claude does not need a daily re-login.
- Menu bar shows **worst of all** or a single provider, with the provider’s
  actual brand mark and color.
- `usage_status` tool so the agent can answer “which account has quota left?”.

---

## Architecture

```
~/.codex/auth.json ─┐
~/.grok/auth.json  ─┼─ read-only ──► DSH plugin Host  ──► ~/.dsh/usage-monitor/state.json
CC Switch DB       ─┤                 (discovery, adapters,        │
Claude Keychain    ─┘                  scheduler, reset events)     │
                                                                   │
                 authenticated /api/usage-monitor/state ◄──────────┘
                            │
                            ▼
                 DeepSeek Harness Web UI
                 (sidebar panel, composer strip, toasts)

                 menu-bar helper ── reads the same state file
                                 └─ refresh.request ──► DSH plugin
```

- The browser never receives a credential; it gets labels, percentages and
  reset times over the existing authenticated `/api` bridge.
- The menu-bar helper does not call providers itself. It reads the local
  snapshot and asks the plugin to refresh through a small request file.
- Provider logos in the helper are trademarks of their owners (see `NOTICE`).

More detail: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Repository layout

```
.
├── plugin/                 DeepSeek Harness bundle
│   ├── index.js            Host half: discovery, adapters, routes, tool
│   ├── client.js           Browser half: panel, dock strip, toasts
│   ├── lib/                Accounts, providers, state, utils
│   ├── locale/             Plugin Manager metadata (en, zh)
│   ├── cordis.patch.yml    Bundle default config
│   └── package.json
├── menu-bar/               Native macOS menu-bar app
│   ├── Host/               MenuBarExtra app, loopback state server, Refresh
│   ├── Shared/             Snapshot models and formatting
│   ├── Widget/             Experimental WidgetKit extension
│   ├── project.yml         XcodeGen project definition
│   └── README.md
├── docs/ARCHITECTURE.md
├── LICENSE
└── NOTICE
```

---

## Requirements

| Piece | Needs |
|---|---|
| DSH plugin | DeepSeek Harness with Plugin Manager; Node runtime is provided by DSH |
| Codex | Codex CLI signed in (`~/.codex/auth.json`) |
| Claude | Claude Code CLI signed in with an **official subscription account** (macOS Keychain, or `~/.claude/.credentials.json`) |
| Grok | Grok CLI signed in (`~/.grok/auth.json`) |
| Optional multi-account | CC Switch (`~/.cc-switch/cc-switch.db`) |
| Menu-bar app | macOS 14+, Xcode 15+ (tested with Xcode 27 / Swift 6.4), XcodeGen |

Windows/Linux DSH hosts can use the plugin; the menu-bar app is macOS only.
Claude automatic refresh uses the macOS Keychain and is macOS only; on other
platforms the Claude credential is read-only.

---

## Setup on a new machine

### 1. Clone the repository

```bash
git clone https://github.com/cheungringo420/dsh-usage-monitor.git
cd dsh-usage-monitor
```

Keep the checkout somewhere stable. The DSH profile links to `plugin/` rather
than copying it, so moving the checkout later requires reinstalling the bundle.

### 2. Install the DSH plugin

The plugin is a local bundle; it is not published to npm. Install it through
DeepSeek Harness’s **Plugin Manager**, which links the package into the active
profile:

1. Open DeepSeek Harness.
2. Start a session and ask the agent to install the local bundle at
   `<absolute-path>/plugin` (the agent uses `plugin_manager` with
   `install_bundle`).
3. Wait for the plugin row to become active, then refresh the Web page once.

You should see a gauge in the sidebar and a **Usage Monitor** strip under the
composer. If the panel does not appear, see [Troubleshooting](#troubleshooting).

### 3. Sign in to the provider CLIs

The plugin never asks for credentials in its UI; it reads the credentials your
CLIs already store.

```bash
# Codex / ChatGPT
codex login

# Claude Code: use the subscription account, not a relay/API key
claude
# then inside Claude Code:
/login
# optionally verify:
/usage

# Grok
grok login
```

Claude notes:

- Use the **same Claude account** as Claude Desktop if you want the numbers to
  match; Anthropic shares one usage pool across claude.ai, Claude Code and
  Claude Desktop.
- Do **not** use `claude setup-token` for quota. It creates an inference-only
  token that lacks the `user:profile` scope required by the usage endpoint.
- Do **not** use a third-party relay/API-key provider for the Claude card; it
  has no subscription usage endpoint.
- The plugin can auto-refresh the Claude Code access token from the Keychain;
  see [Claude token refresh](#claude-token-refresh).

### 4. Build and run the macOS menu-bar app

```bash
brew install xcodegen
cd menu-bar

# recommended: change the bundle id prefix to your own GitHub username
# edit project.yml -> options.bundleIdPrefix and the two PRODUCT_BUNDLE_IDENTIFIERs

xcodegen generate
xcodebuild -project UsageWidget.xcodeproj \
  -scheme UsageWidgetHost -configuration Release \
  -derivedDataPath /tmp/UsageWidgetDerived build

ditto /tmp/UsageWidgetDerived/Build/Products/Release/UsageWidget.app \
  /Applications/UsageWidget.app
xattr -cr /Applications/UsageWidget.app
open /Applications/UsageWidget.app
```

The app is menu-bar only (`LSUIElement`), ad-hoc signed, and needs no Apple
developer account for the menu-bar surface. Enable **Launch at Login** in its
popover. If macOS rejects the ad-hoc app as a login item, add
`/Applications/UsageWidget.app` under **System Settings → General → Login
Items**.

The embedded WidgetKit extension is **experimental** and does not appear under
*Edit Widgets* when the app is ad-hoc signed (`chronod` ignores it). Sign with
an Apple Development/Developer ID identity and reinstall if you want to try the
desktop widget; the menu-bar app is the supported surface.

### 5. Open it

- **In-app:** sidebar gauge → Usage Monitor, or the strip under the composer.
- **Menu bar:** gauge + tightest percentage. Click for the full popover; use the
  **Menu bar** picker to choose *Worst of all*, Codex, Claude or Grok.

---

## Configuration

The plugin default config lives in `plugin/cordis.patch.yml`. Override it from
the active profile at `$DSH_HOME/profiles/<profile>/cordis.patch.yml` (usually
`~/.dsh/profiles/<profile>/cordis.patch.yml`):

```yaml
- id: usage-monitor
  name: '@local/usage-monitor'
  config:
    pollSeconds: 300          # provider fetch cadence, 60–3600
    refreshMinSeconds: 120    # per-account floor, 30–3600
    claudeRefreshTokens: true # auto-refresh Claude Code OAuth from Keychain
    notifications:
      toast: true             # in-app reset/refill toasts
      macos: false            # native macOS notifications
      lowThreshold: 10        # warn once at/below this % remaining
    discovery:
      cli: true               # Codex/Claude/Grok CLI stores
      ccSwitch: true          # CC Switch DB, read-only
    ui:
      dock: true              # composer strip
    accounts: []              # optional manual accounts, see below
```

Config is replaced wholesale by an id-targeted patch; omitted fields fall back
to the defaults above.

### Manual accounts

```yaml
    accounts:
      - id: codex-work
        provider: codex
        label: Codex · work
        tokenFile: ~/.secrets/codex-work.json
      - id: claude-team
        provider: claude
        label: Claude · team
        tokenEnv: CLAUDE_TEAM_TOKEN
```

A token file may be a raw token or any of the CLI JSON shapes
(`.key`, `.tokens.access_token`, `.claudeAiOauth.accessToken`, or an entry with
`key`). Manual Codex accounts can also provide `accountId` and `plan`.

### Multiple Codex accounts

Codex identity comes from the **JWT user**, not the stored team `account_id`.
Two people in one ChatGPT team share the account id but have distinct usage, so
both are shown.

- CC Switch rows are read with `sqlite3 -readonly`; expired tokens are skipped
  and copies of one user collapse into one card.
- Extra Codex CLI homes are discovered automatically:
  `CODEX_HOME=~/.codex-work codex login` makes `~/.codex-work/auth.json` visible.
- Or add a manual `tokenFile` entry.

---

## Refresh rates

| Layer | Cadence |
|---|---|
| Provider usage API calls | every **5 min** per account |
| Per-account floor (background) | **2 min**; manual Refresh bypasses it |
| DSH scheduler check | every 30 s; fetches when the snapshot is 5 min old |
| In-app panel `/api` poll | every 60 s; host refreshes when stale |
| Menu-bar helper state read | every 10 s; countdown text every 30 s |
| Menu-bar **Refresh** | asks the plugin to fetch all providers immediately |
| STALE marker | 15 min without a new snapshot |

These are metadata requests, not model requests: they consume network/rate-limit
budget, not inference tokens or subscription quota. Grok’s billing endpoint has
an observed ~5-minute cooldown, so avoid lowering the cadence much further.

---

## Data sources

| Provider | Credential (read locally) | Endpoint |
|---|---|---|
| Codex | `~/.codex/auth.json`, `~/.codex-*/auth.json`, CC Switch rows | `GET https://chatgpt.com/backend-api/wham/usage` |
| Claude | macOS Keychain `Claude Code-credentials`, `~/.claude/.credentials.json`, `CLAUDE_CODE_OAUTH_TOKEN` | `GET https://api.anthropic.com/api/oauth/usage` |
| Grok | `~/.grok/auth.json` | `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` |
| Manual | `tokenEnv` / `tokenFile` in config | provider endpoint |

CC Switch is opened with `sqlite3 -readonly` and never written.

---

## Claude token refresh

Claude Code OAuth access tokens last about eight hours. With
`claudeRefreshTokens: true` (default), the plugin:

1. Reads the Keychain item when the token is within two minutes of expiry, or
   after a 401.
2. Exchanges the refresh token at
   `https://platform.claude.com/v1/oauth/token` with the Claude Code client id.
3. Writes the new access token and rotated refresh token back to
   `Claude Code-credentials`, preserving the existing `mcpOAuth` entries.
4. Updates its in-memory account and retries the usage request.

The refresh token lasts roughly 27 days. After it expires, or after a
logout/password change, sign in to Claude Code once more:

```bash
claude
/login
```

Set `claudeRefreshTokens: false` for strictly read-only behavior. The plugin
never writes tokens to its state file, routes, logs, the helper, or the browser.

---

## Privacy and security

- Credentials are read into process memory only. Tokens never enter
  `state.json`, HTTP responses, the menu-bar app, or logs.
- `$DSH_HOME/usage-monitor/state.json` is mode 0600 and contains account labels,
  emails, percentages, reset times and sanitized errors. The menu-bar helper
  needs to read it.
- Claude refresh writes only the Keychain item that Claude Code already owns.
  Disable it with `claudeRefreshTokens: false`.
- CC Switch is read-only.
- The menu-bar helper serves a loopback-only endpoint on `127.0.0.1:47821` with a
  static local token, and accepts refresh requests through
  `usage-monitor/refresh.request` next to the state file. Both are local,
  same-user mechanisms; DeepSeek Harness must be running.
- The monitor calls provider metadata endpoints only. It never sends prompts or
  consumes model tokens.

---

## Troubleshooting

- **No sidebar icon / no panel** — confirm the bundle is installed and active in
  Plugin Manager, then refresh the Web page. The plugin row id is
  `usage-monitor`; package name `@local/usage-monitor`.
- **No accounts** — sign in with `codex login`, `claude` → `/login`, and
  `grok login`; check `~/.codex/auth.json`, the Claude Keychain item, and
  `~/.grok/auth.json`. The empty state also lists the commands.
- **Claude “not signed in”** — only an official Claude Code OAuth login exposes
  quota. A relay `ANTHROPIC_AUTH_TOKEN` or `claude setup-token` will not work.
- **Claude HTTP 401** — auto-refresh could not renew the credential (refresh
  token expired/revoked or Keychain write failed). Sign in to Claude Code again.
- **Menu bar says STALE** — DeepSeek Harness is closed or the plugin has not
  written a snapshot for 15 minutes. Start DSH; press **Refresh**.
- **Refresh changes nothing** — DSH must be running for the helper’s request file
  to be picked up. The plugin watches it every two seconds. The in-app Refresh
  uses the authenticated `/api/usage-monitor/refresh` route instead.
- **Only one Codex account** — the second login must be a different JWT user;
  use another ChatGPT account, a separate `CODEX_HOME`, or a manual token file.
- **Menu-bar build fails with “resource fork / detritus”** — build under
  `/tmp` (or another non-file-provider path) and clear xattrs:
  `xattr -cr /Applications/UsageWidget.app`.
- **Widget missing from Edit Widgets** — expected for ad-hoc builds; see
  [menu-bar/README.md](menu-bar/README.md).
- **Port 47821 busy** — quit other copies of the helper before launching.

---

## Uninstall

1. Menu bar: **Quit**, remove `/Applications/UsageWidget.app`, and remove it from
   Login Items.
2. Plugin: disable or remove the `usage-monitor` bundle in Plugin Manager.
3. Optional data: remove `$DSH_HOME/usage-monitor/` (state snapshots and refresh
   request) and, if you enabled it, no provider credential was modified except
   Claude Code’s own Keychain item.

---

## License and trademarks

Code is MIT licensed; see [LICENSE](LICENSE).

The bundled OpenAI knot, Claude starburst and Grok slash are trademarks of their
respective owners, used only to identify the services in a local dashboard. They
are **not** covered by the MIT license. See [NOTICE](NOTICE); replace or remove
the marks before redistributing them commercially.

---

## Contributing

Issues and pull requests are welcome. The plugin and helper have separate
READMEs with their implementation details:

- [plugin/README.md](plugin/README.md)
- [menu-bar/README.md](menu-bar/README.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
