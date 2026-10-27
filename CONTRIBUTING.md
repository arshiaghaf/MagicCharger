# Contributing

Open an issue describing the problem or proposed change before substantial work. Use the [bug report](https://github.com/arshiaghaf/magic-charger/issues/new/choose) for reproducible failures and the [hardware validation checklist](docs/VALIDATION.md#hardware-validation-checklist) for device evidence. Keep device reports anonymous: model family, OS version and relevant charging properties are enough. Do not post raw registry dumps, addresses, serials or personalized names.

Use an installed compatible Swift 6.0+ macOS toolchain. Run:

```sh
swift test
sh build-app.sh
codesign --verify --strict "build/Magic Charger.app"
```

Set `DEVELOPER_DIR` locally if needed; do not change global developer selection for the project. The app has no third-party runtime dependencies; DMG layout preparation fetches a pinned MIT-licensed DSStore package used only by build tooling. Add focused tests for meaningful behavior changes. Simulated fixtures must never enter live UI or notifications.

Use short standard commit subjects such as `fix: preserve charging continuity`. Open a draft PR while work is in progress, with **Summary** and **Validation** sections. Record actual commands/results and distinguish deterministic, CI and hardware verification. Mark ready once the change is ready. Before merging, require review of the final head, passing checks and verified resolution of review concerns. Changes after approval require review of the new head. Do not claim broader hardware support from a single model.

Code and documentation contributions are licensed under MIT. The existing app icon artwork has separate terms in [ARTWORK.md](ARTWORK.md); agree on terms before contributing new artwork. Do not copy incompatible third-party implementation or distribute Apple SF Symbols as MIT assets. Keep build outputs and private local agent notes untracked.
