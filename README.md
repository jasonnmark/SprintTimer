# SprintTimer

A SwiftUI / SwiftData app for timing sprints on Apple Watch, with an iPhone companion for history, notes, and export. I built it for my wife so she could time her 100s, 200s, 400s, hurdles, and whatever else she runs.

It is provided **as-is** with no warranty whatsoever. You are welcome to use it, modify it, sell it, dissect it, marry it, or do anything else you want with it. I don't owe you support and you don't owe me anything.

Built mostly with [Claude Code](https://www.anthropic.com/claude-code).

## What's inside

- **Apple Watch app** — start, time, and save sprints with tap-to-start / motion / countdown modes. Hands-free finish capture via Double Tap on Series 9 / Ultra 2 and later.
- **iPhone app** — full history with per-run edits, custom run types (e.g. "200m Hurdles"), CSV / JSON export, iCloud backup, optional weather and GPS metadata per sprint.
- **Watch complication** — last run time, distance, today's run count.

## Building

Open `SprintTimer.xcodeproj` in Xcode. You'll need to set your own development team and provisioning profiles. The OpenWeatherMap integration is optional — enter your own API key in Settings if you want weather data attached to each sprint.

## License

MIT. See [LICENSE](LICENSE) for the full text. Short version: do whatever you want, just keep the copyright notice in copies you distribute.
