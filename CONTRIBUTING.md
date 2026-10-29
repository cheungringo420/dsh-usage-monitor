# Contributing

Thanks for considering a contribution. This project touches real provider
credentials, so a few rules matter more than usual.

## Ground rules

- **Never commit credentials, tokens, `state.json`, Keychain dumps, account
  emails, or personal screenshots.** Use example labels such as
  `codex@example.com`.
- Keep provider adapters isolated in `plugin/lib/providers.js`. A failure in one
  provider must not break the others.
- Do not add telemetry, analytics, or calls to model inference endpoints.
- The menu-bar helper must stay a local reader. It may read the state file and
  write `refresh.request`; it must not read provider credentials.
- Update `README.md` / `docs/ARCHITECTURE.md` when behaviour or setup changes.

## Development setup

### Plugin

The bundle is installed into a DeepSeek Harness profile through Plugin Manager.
For iteration, ask the agent to install the local `plugin/` directory, or use the
profile's `link:` dependency. Host changes need a bundle reload (toggle the
plugin row or restart DSH); client changes hot-reload in an open page.

Checks before pushing:

```bash
find plugin -name '*.js' -print0 | xargs -0 -n1 node --check
```

### Menu-bar app

```bash
cd menu-bar
brew install xcodegen
xcodegen generate
xcodebuild -project UsageWidget.xcodeproj \
  -scheme UsageWidgetHost -configuration Release \
  -derivedDataPath /tmp/UsageWidgetDerived build
```

Build under `/tmp` if the checkout lives on a file-provider volume; otherwise
codesign can fail with a resource-fork/detritus error. Clear xattrs on the
installed app: `xattr -cr /Applications/UsageWidget.app`.

Set your own bundle id prefix in `menu-bar/project.yml` before shipping a build.

## Pull requests

1. Keep changes focused and describe the user-visible effect.
2. Include a short test note (what you clicked, what you observed).
3. Do not include screenshots with personal account data.
4. Update the changelog for user-visible changes.
5. Make sure the `checks` workflow passes.

## Reporting security issues

See [SECURITY.md](SECURITY.md). Do not open a public issue for a credential leak
or a way to read another user's data.
