# Architecture

The AppKit accessory app owns independent monitoring, controls and per-device NSStatusItems. LSUIElement avoids a permanent Dock icon. Launch/reopen presents one controls window; closing it keeps the process alive.

Public IOKit registry matching/termination callbacks and interest hints trigger coalesced background snapshots. Bounded fallback polling is 30 seconds idle/unknown and 10 seconds charging. UI changes occur on the main thread. Sleep invalidates in-flight work and visible items; wake resamples. Driver freshness is not inferred from polling time.

ChargingDecoder uses tri-state evidence and narrow model/OS profiles. Conflicting duplicate observations are suppressed. Installation-keyed identity supports conservative notification continuity across reconnects. Menu icons cache the device glyph and its visibility preference; percentages and status emoji update as text without animation timers. Full takes precedence over the charging emoji at 100% only when the reading is already eligible for display; idle, unknown and stale readings remain hidden.

ChargingStarts needs a recent verified idle baseline. Thresholds persists minimal session state and consumes historical/disabled crossings. The highest enabled eligible milestone wins. UserNotifications authorization is independent of alert preferences; pending and async disabled alerts are guarded. Native notification submission is not proof of visible presentation.

References: [IOKit](https://developer.apple.com/documentation/iokit), [Apple registry notification implementation](https://github.com/apple-oss-distributions/IOKitUser/blob/main/ionotifyCB.c), [NSStatusBar](https://developer.apple.com/documentation/appkit/nsstatusbar). Private accessory IOPowerSources APIs are intentionally unused.
