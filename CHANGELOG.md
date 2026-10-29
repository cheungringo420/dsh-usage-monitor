# Changelog

All notable changes are documented here. The project follows
[Semantic Versioning](https://semver.org/).

## [1.1.0] — 2026-10-29

### Added

- **Standalone menu-bar mode.** The macOS app now discovers Codex, Claude and
  Grok credentials and calls the providers' usage APIs itself. DeepSeek Harness
  is no longer required for the menu-bar number.
- Direct provider engine with Codex JWT/team identity, CC Switch discovery,
  Claude Keychain refresh and write-back, and Grok product/balance parsing.
- The app writes its own 0600 snapshot at
  `~/Library/Application Support/DSHUsageMonitor/snapshot.json`; the DSH
  snapshot is only a one-time fallback.
- Direct **Refresh** (no `refresh.request`/DSH process needed).
- Prebuilt universal menu-bar helper `UsageWidget-1.1.0.zip`.

### Fixed

- Numeric `0` values were incorrectly treated as booleans, hiding windows whose
  used percentage was 0 and preventing Claude token refresh when the stored
  expiry was `0`.
- The menu-bar app no longer shows “Waiting for DeepSeek Harness” when run on a
  machine without the harness.

## [1.0.0] — 2026-10-29

First public release.

### Added

- DeepSeek Harness bundle for Codex, Claude and Grok quota.
- In-app sidebar panel, composer strip, reset/refill toasts, and a
  `usage_status` agent tool.
- Native macOS menu-bar companion with provider marks, colours, a
  Worst-of-all/per-provider picker, live countdowns and a Refresh button.
- Multiple accounts per provider, including Codex users that share a ChatGPT
  team id (identity from the JWT user, not the team id).
- CC Switch read-only discovery, extra `CODEX_HOME` homes, and manual
  `tokenEnv` / `tokenFile` accounts.
- Claude Code OAuth auto-refresh from the macOS Keychain with write-back of the
  rotated access/refresh tokens.
- Provider-branded menu-bar images (OpenAI knot, Claude starburst, Grok slash).
- Prebuilt menu-bar helper release, README screenshots, architecture docs, CI
  syntax checks, issue templates, security policy and MIT license.

### Known limitations

- The helper is ad-hoc signed, not notarized.
- The WidgetKit extension is included but ignored by `chronod` for ad-hoc builds.
- Claude auto-refresh is macOS-only and needs a valid refresh token (about 27
  days).
- Provider usage endpoints are undocumented and may change.

[1.1.0]: https://github.com/cheungringo420/dsh-usage-monitor/releases/tag/v1.1.0
[1.0.0]: https://github.com/cheungringo420/dsh-usage-monitor/releases/tag/v1.0.0
