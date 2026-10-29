# Usage Widget — macOS menu-bar companion

A small native macOS app that reads the DSH Usage Monitor snapshot and shows
the tightest Codex/Grok window at a glance in the menu bar.

## Installed

- App: `/Applications/UsageWidget.app` (menu-bar app, no Dock icon)
- Menu bar: gauge icon + worst remaining percent (currently `8%`)
- Click it for the Codex/Grok cards, refresh, and login-item toggle.

## Data

It reads `$DSH_HOME/usage-monitor/state.json (default ~/.dsh)`, written by the DSH plugin every
five minutes. Only labels, percentages and reset times — no credentials.

**Refresh** writes a `refresh.request` file next to the state. The DSH plugin
watches for it and fetches every provider immediately; the helper then polls the
state and updates the cards. DeepSeek Harness must be running for this. The
Claude access token is refreshed automatically by the plugin (written back to
the macOS Keychain), so no daily re-login is needed.

`STALE` appears when the snapshot is older than 15 minutes, which usually means
DeepSeek Harness is closed or the plugin has not refreshed yet. Press
**Refresh** after DSH starts.

## Build from source

```bash
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

The source is ad-hoc signed ("Sign to Run Locally"), which is fine for the
menu-bar app.

## The WidgetKit extension

`UsageWidgetExtension` is built and embedded in the app and appears in
`pluginkit`, but macOS `chronod` purges it because the app is ad-hoc signed:

```
Requested to add extension, but purging instead because we shouldn't cache it
… isApple? false
```

It therefore does not appear under *Edit Widgets*. To finish it, sign in to
Xcode with an Apple ID (free Personal Team is enough), set `DEVELOPMENT_TEAM`
in `project.yml`, rebuild and reinstall. The widget talks to the helper over
`127.0.0.1:47821`, so no App Group is needed.

## Login item

Use **Launch at Login** in the menu. If macOS rejects the ad-hoc app as a login
item, add `/Applications/UsageWidget.app` in System Settings → General →
Login Items, or ask for a LaunchAgent plist.

## Troubleshooting

- **STALE** — DSH is closed or the plugin snapshot is older than 15 minutes.
- **No menu bar item** — launch `/Applications/UsageWidget.app` again.
- **Port 47821 busy** — quit other copies of the helper; only one can own the
  loopback endpoint.
