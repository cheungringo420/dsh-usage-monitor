# Usage Widget — standalone macOS menu-bar app

A native SwiftUI menu-bar app that shows the tightest remaining Codex, Claude or
Grok window at a glance, with a popover for every local account.

**DeepSeek Harness is not required.** The app discovers local CLI credentials and
calls the providers' usage endpoints directly.

## Install

Download the latest release (`UsageWidget-1.1.0.zip`) and install:

```bash
unzip ~/Downloads/UsageWidget-1.1.0.zip -d /tmp
ditto /tmp/UsageWidget.app /Applications/UsageWidget.app
xattr -cr /Applications/UsageWidget.app
open /Applications/UsageWidget.app
```

The app is ad-hoc signed, not notarized. macOS may ask you to confirm the first
launch; right-click → **Open** if needed.

## What it reads

| Provider | Local credential | Usage API |
|---|---|---|
| Codex | `~/.codex/auth.json`, `~/.codex-*/auth.json`, CC Switch SQLite | ChatGPT backend usage endpoint |
| Claude | macOS Keychain `Claude Code-credentials`, `~/.claude/.credentials.json`, `CLAUDE_CODE_OAUTH_TOKEN` | Anthropic OAuth usage endpoint |
| Grok | `~/.grok/auth.json` | Grok CLI billing endpoint |

The app writes its own snapshot to:

```
~/Library/Application Support/DSHUsageMonitor/snapshot.json   (0600)
```

No tokens are stored there. If that file does not exist yet, the app falls back
once to a DSH plugin snapshot, but it does not require DSH.

## Refresh

- Fetches on launch and every **5 minutes**.
- **Refresh** in the popover fetches every provider immediately.
- Claude Code OAuth is refreshed from the Keychain before expiry and written
  back to the same Keychain item, preserving `mcpOAuth`.
- `STALE` appears when the snapshot is older than 15 minutes.

## Menu bar

- The label shows the worst remaining window for *Worst of all*, or a pinned
  provider (Codex / Claude / Grok).
- The icon is the provider mark in that provider's colour.
- The popover groups accounts by provider, with bars, used/remaining
  percentages, absolute resets and live countdowns.
- **Launch at Login** is in the popover footer.

## Build from source

```bash
brew install xcodegen
cd menu-bar
xcodegen generate
xcodebuild -project UsageWidget.xcodeproj \
  -scheme UsageWidgetHost -configuration Release \
  -derivedDataPath /tmp/UsageWidgetDerived build
ditto /tmp/UsageWidgetDerived/Build/Products/Release/UsageWidget.app \
  /Applications/UsageWidget.app
xattr -cr /Applications/UsageWidget.app
open /Applications/UsageWidget.app
```

Change `options.bundleIdPrefix` and the two `PRODUCT_BUNDLE_IDENTIFIER`s in
`project.yml` to your own prefix before shipping your own build. The app is
ad-hoc signed ("Sign to Run Locally"), which is fine for the menu-bar surface.

## WidgetKit extension

`UsageWidgetExtension` is built and embedded, but macOS `chronod` ignores widget
extensions from ad-hoc-signed apps. It therefore does not appear under *Edit
Widgets*. Sign with an Apple Development/Developer ID identity, set
`DEVELOPMENT_TEAM` in `project.yml`, rebuild and reinstall to use it. The widget
reads the helper's loopback endpoint on `127.0.0.1:47821`; no App Group is
needed.

## Login item

Use **Launch at Login** in the popover. If macOS rejects the ad-hoc app as a
login item, add `/Applications/UsageWidget.app` under System Settings → General →
Login Items.

## Troubleshooting

- **No accounts** — run `codex login`, `claude` → `/login`, or `grok login`,
  then press **Refresh**.
- **Menu bar shows an em dash** — no snapshot yet; open the popover and check
  the empty-state error.
- **Claude 401** — auto-refresh could not renew the token; run `claude` →
  `/login`.
- **STALE** — press **Refresh**; the app refreshes every five minutes while
  running.
- **No menu bar item** — launch `/Applications/UsageWidget.app` again.
- **Port 47821 busy** — quit other copies of the helper; only one can own the
  loopback endpoint.
- **Build error: resource fork / detritus** — build under `/tmp` and run
  `xattr -cr` on the installed app.
