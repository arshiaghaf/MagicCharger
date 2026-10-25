# Magic Charger

Magic Charger is a macOS menu-bar utility for Magic Keyboard and Magic Mouse charging notifications. Its reminders support charging habits aimed at preserving long-term accessory battery health. It shows a separate battery level for each supported accessory while verified charging evidence is present, then removes the menu-bar item when that evidence ends. Monitoring continues in the background.

Optional local notifications tell you when charging starts and when a device reaches 78%, 80%, or 100%. You choose which alerts are enabled. Magic Charger does not stop charging or control power to an accessory.

## What Magic Charger Does

Magic Charger reads relevant accessory battery information through IOKit. It shows charging devices in the menu bar in this order: device glyph, exact percentage, and status emoji (⚡️ while charging, 🔋 at 100%). When no supported device has verified charging evidence, the menu-bar items disappear; reopen the app from Finder or Spotlight for controls and Quit.

The controls window lets you choose which menu-bar elements and alerts to show, check notification permission, and send one clearly labeled test notification without simulating charging. Closing the window keeps monitoring. There is no permanent Dock icon. **Launch at Login** is off by default and can be enabled in General.

## Features

- Shows each verified charging accessory separately, without averaging battery levels
- Offers independent menu-bar choices for the device glyph, percentage, and status emoji
- Offers independent Charging Started, Unplug Soon (78%), Unplug Reminder (80%), and Fully Charged (100%) alerts; the 80% reminder prompts you to unplug to help preserve long-term battery health
- Consumes skipped and disabled alert milestones so old readings do not trigger later reminders
- Keeps controls, notification settings, a test notification, and Quit available when the menu bar is empty
- Opens the official GitHub Releases page from **View Releases**; it does not download or install updates

## Install

Magic Charger is currently a source preview. There is no downloadable release yet.

### GitHub Releases (DMG) — WIP

A downloadable DMG is not available yet. When one is published, it will appear on [GitHub Releases](https://github.com/arshiaghaf/MagicCharger/releases). The current release-preparation DMG contains an ARM64 app; Intel and universal distribution have not been verified.

### Homebrew — WIP

Homebrew installation for Magic Charger is WIP. The tap, cask, and installation command are TBA.

### Build from source

Requires macOS 14 or later and an installed compatible Xcode/Swift 6.0-or-later toolchain.

```sh
git clone https://github.com/arshiaghaf/MagicCharger.git
cd MagicCharger
sh build-app.sh
open "build/Magic Charger.app"
```

The script builds an ad-hoc signed local app. It uses an explicitly supplied `DEVELOPER_DIR`, otherwise an installed Xcode in `/Applications/Xcode.app`, otherwise the active developer selection. It does not change the global selection. Use `CONFIGURATION=release sh build-app.sh` for an optimized local build; the default is debug. Run `swift test` with the same compatible developer directory for deterministic checks.

### First launch of an unnotarized download

Magic Charger builds do not have a Developer ID signature or notarization. If a future official download comes from a source you trust, you are certain it has not been tampered with, and macOS says the developer cannot be verified or Apple cannot check the app for malicious software:

1. Place Magic Charger in Applications and try opening it. Dismiss the warning if one appears.
2. Open **System Settings > Privacy & Security**, scroll to **Security**, then choose **Open Anyway** for Magic Charger.
3. Confirm with **Open** and authenticate if macOS asks. Try opening the app again if needed.

![Apple's macOS Sequoia Privacy & Security example showing Open Anyway for Example App](docs/images/macos-sequoia-open-anyway.png)

Apple's macOS Sequoia (macOS 15) example shows “Example App,” not Magic Charger. [Image source](https://cdsassets.apple.com/live/7WUAS350/images/macos/sequoia/macos-sequoia-system-settings-privacy-and-security-open-app-anyway.png). The Apple image is not licensed under this project's MIT License.

Do not override a warning that the app **will damage your computer** or **is damaged**. Read [Apple's guidance on safely opening apps](https://support.apple.com/en-us/102445) before approving an unnotarized app. These steps do not change the system-wide app security setting.

## Limitations

The macOS 14 deployment target does not establish charging detection on macOS 14. The app recognizes flag-based charging for these two Bluetooth service profiles; their cable transitions were physically observed on macOS 27.2:

| Accessory | Profile | Current evidence |
| --- | --- | --- |
| Magic Mouse | Vendor 76, product 803 | User-confirmed cable transitions, charging display, and automatic menu-bar appearance/removal |
| Magic Keyboard | Vendor 76, product 801 | User-confirmed cable transitions; live charging UI still needs validation |

For these profiles, flag 3 with a valid percentage below 100% indicates charging and flag 4 indicates not charging. The decoder applies those recognized values across macOS versions, including its flag-based full-charge evidence, while keeping unknown flags unknown. These are narrow observations, not an Apple guarantee of future flag semantics or a general flag specification. Recognized explicit Boolean charging properties can also provide charging-state evidence. Missing, conflicting, stale, or unvalidated readings stay unknown; USB presence alone is not enough.

- At 100%, the menu-bar item may disappear because active charging is uncertain. A supported full reading can still notify after continuous charging evidence; it does not prove that charging current stopped or power bypasses the battery.
- Registry events prompt updates, with fallback polling every 30 seconds when idle or unknown and every 10 seconds while charging. Cached driver values may still be stale, so exact alert percentages are not guaranteed.
- An entire charging cycle while the app is not running cannot be reconstructed. Missing stable device identity limits reconnect deduplication.
- Alerts require macOS notification permission. Focus and screen-sharing settings can suppress banners even when Notification Center receives an alert.
- Real 78%, 80%, and 100% crossings, simultaneous charging, keyboard charging UI, sleep/wake, broader hardware/OS support, and banner presentation still need hardware validation.
- App Store sandbox compatibility and Intel builds remain unverified.
- Notifications are optional reminders. Magic Charger does not provide automatic charge cutoff, a precise time-to-target estimate, or a guaranteed battery-health improvement.

See the [validation evidence and hardware checklist](docs/VALIDATION.md) before reporting a new device result. Include only generic model and OS details in a [bug report](https://github.com/arshiaghaf/MagicCharger/issues/new/choose); do not post raw identifiers or registry dumps.

## Moving from an Earlier Preview

Earlier previews used bundle ID `local.magiccharger.app`; current builds use `co.arshia.magiccharger`. macOS treats them as separate apps. Notification permission, preferences, and local alert-session history start fresh, while the older data remains in place. If you enabled Launch at Login in an older preview, disable that entry before quitting it and opening a new build to avoid duplicate monitoring. See [Support](SUPPORT.md) for recovery steps.

## Privacy and Security

Magic Charger has no network client, analytics, account, or backend. It reads relevant accessory telemetry and never captures keyboard or mouse input. A supported accessory address is used transiently to derive an installation-keyed local identity; raw addresses, serials, and personalized names are not stored or logged. Local preferences and bounded notification-session history use UserDefaults.

See [Privacy](docs/PRIVACY.md) for details and [Security](SECURITY.md) for reporting suspected vulnerabilities. Charging evidence depends on accessory registry properties whose semantics may vary across hardware and macOS versions.

The Magic Mouse glyph is Apple's runtime `magicmouse` SF Symbol. Apple symbol artwork is not bundled under this project's MIT license.

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md). Keep changes focused and distinguish deterministic tests from real-device checks.

Developer documentation:

- [Architecture](docs/ARCHITECTURE.md)
- [Validation](docs/VALIDATION.md)
- [Changelog](CHANGELOG.md)

CI builds and tests the app and verifies bundle packaging. It cannot validate physical charging or visible notifications.

## License

Magic Charger software and documentation, including compiled and generated forms, are licensed under the [MIT License](LICENSE). The app icon and DMG background artwork are [reserved separately](ARTWORK.md); the Apple example image and runtime SF Symbol are third-party materials.

Copyright (c) 2026 Arshia Ghaf.
