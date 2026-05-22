import WidgetKit
import SwiftUI

// MARK: - Stopwatch launcher widget

struct LauncherEntry: TimelineEntry {
    let date: Date
}

struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry {
        LauncherEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) {
        completion(LauncherEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        // Static icon — no refreshes needed.
        completion(Timeline(entries: [LauncherEntry(date: Date())], policy: .never))
    }
}

struct LauncherView: View {
    @Environment(\.widgetFamily) var family

    // SwiftUI on watchOS doesn't always honor template-rendering-intent from the asset
    // catalog; .renderingMode(.template) on the SwiftUI Image makes it explicit so
    // .widgetAccentable() can actually tint the alpha mask.
    private var logo: Image {
        Image("AppLogo").renderingMode(.template)
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            logo
                .resizable()
                .scaledToFit()
                .widgetAccentable()
        case .accessoryCorner:
            logo
                .resizable()
                .scaledToFit()
                .widgetAccentable()
                .widgetLabel { Text("Sprint") }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                logo
                    .resizable()
                    .scaledToFit()
                    .widgetAccentable()
                    .frame(width: 36, height: 36)
                Text("Sprint Timer")
                    .font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 0)
            }
        case .accessoryInline:
            // Inline complications only support text + an SF Symbol, not bundled images.
            Label("Sprint Timer", systemImage: "stopwatch.fill")
        default:
            logo
                .resizable()
                .scaledToFit()
                .widgetAccentable()
        }
    }
}

struct SprintTimerLauncherWidget: Widget {
    let kind: String = "SprintTimerLauncher"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LauncherProvider()) { entry in
            LauncherView()
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Sprint Timer")
        .description("Tap to open Sprint Timer.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Stats widget (last run time + today's count)

struct StatsEntry: TimelineEntry {
    let date: Date
    let lastRunTime: String?
    let lastRunDistance: Int?
    let todayRunCount: Int
}

struct StatsProvider: TimelineProvider {
    private let appGroupID = "group.com.JasonMark.SprintTimer"

    func placeholder(in context: Context) -> StatsEntry {
        StatsEntry(date: Date(), lastRunTime: "12.345", lastRunDistance: 100, todayRunCount: 3)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatsEntry) -> Void) {
        completion(fetchCurrentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsEntry>) -> Void) {
        let entry = fetchCurrentEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func fetchCurrentEntry() -> StatsEntry {
        let defaults = UserDefaults(suiteName: appGroupID)
        let lastTime = defaults?.string(forKey: "complication.lastRunTime")
        let lastDistance = defaults?.integer(forKey: "complication.lastRunDistance") ?? 0
        let todayCount = defaults?.integer(forKey: "complication.todayRunCount") ?? 0
        return StatsEntry(
            date: Date(),
            lastRunTime: lastTime,
            lastRunDistance: lastDistance == 0 ? nil : lastDistance,
            todayRunCount: todayCount
        )
    }
}

struct StatsView: View {
    var entry: StatsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 12))
                    if let time = entry.lastRunTime {
                        Text(time)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    } else {
                        Text("\(entry.todayRunCount)")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
        case .accessoryCorner:
            Text("\(entry.todayRunCount)")
                .font(.system(size: 20, weight: .bold))
                .widgetLabel { Text("runs") }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 12))
                    Text("Sprint Timer")
                        .font(.system(size: 12, weight: .semibold))
                }
                if let time = entry.lastRunTime, let dist = entry.lastRunDistance {
                    Text("\(dist)m: \(time)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                } else {
                    Text("No runs yet")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                Text("Today: \(entry.todayRunCount) runs")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
        case .accessoryInline:
            if let time = entry.lastRunTime, let dist = entry.lastRunDistance {
                Text("\(dist)m \(time) | \(entry.todayRunCount) today")
            } else {
                Text("Sprint Timer: \(entry.todayRunCount) runs today")
            }
        default:
            Text("\(entry.todayRunCount)")
        }
    }
}

struct SprintTimerStatsWidget: Widget {
    let kind: String = "SprintTimerStats"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatsProvider()) { entry in
            StatsView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Sprint Timer Stats")
        .description("Shows your last run time and today's run count.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

#Preview(as: .accessoryCircular) {
    SprintTimerLauncherWidget()
} timeline: {
    LauncherEntry(date: .now)
}
