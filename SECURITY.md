# Security policy

## Supported versions

The latest release and `main` receive security fixes.

## Reporting a vulnerability

Please use GitHub's **private vulnerability reporting** for this repository
(Security → Report a vulnerability). Do not open a public issue for:

- credential/token exposure;
- a way to read another user's data;
- an authentication bypass in the local helper server;
- a malicious provider response that escapes the adapters.

Include the affected version, steps to reproduce, and the impact. Please do not
paste actual tokens, Keychain values, or account emails; redact them.

## Scope notes

- The standalone menu-bar app reads local Codex/Claude/Grok credentials and calls
  the providers directly. It writes its snapshot to
  `~/Library/Application Support/DSHUsageMonitor/snapshot.json` (mode 0600).
- The menu-bar helper listens on `127.0.0.1:47821` with a static local token. It
  is a same-user, loopback mechanism, not a network service.
- Claude auto-refresh writes the Keychain item Claude Code already owns. It is
  always on in the standalone app; set `claudeRefreshTokens: false` in the
  optional DSH plugin if you want that path read-only.
- Provider usage endpoints are undocumented. A provider response is treated as
  untrusted input; parsers are defensive and errors are sanitized before they
  reach the UI or snapshot.
- Snapshots are mode 0600 and deliberately contain account labels and emails.
  They contain no tokens. Do not share them publicly.

## Dependencies

The plugin uses Node built-ins only. The menu-bar app uses Apple frameworks and
has no third-party Swift packages. Provider marks are documented in
[NOTICE](NOTICE) and are not covered by the MIT license.
