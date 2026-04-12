import WidgetKit
import SwiftUI

struct SprintTimerEntry: TimelineEntry {
    let date: Date
    let lastRunTime: String?
    let lastRunDistance: Int?
    let todayRunCount: Int
}

struct SprintTimerComplicationProvider: TimelineProvider {
    private let appGroupID = "group.com.JasonMark.SprintTimer"

    func placeholder(in context: Context) -> SprintTimerEntry {
        SprintTimerEntry(date: Date(), lastRunTime: "12.345", lastRunDistance: 100, todayRunCount: 3)
    }

    func getSnapshot(in context: Context, completion: @escaping (SprintTimerEntry) -> Void) {
        let entry = fetchCurrentEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SprintTimerEntry>) -> Void) {
        let entry = fetchCurrentEntry()
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func fetchCurrentEntry() -> SprintTimerEntry {
        // Read from shared UserDefaults since we can't access SwiftData from widget
        let defaults = UserDefaults(suiteName: appGroupID)
        let lastTime = defaults?.string(forKey: "complication.lastRunTime")
        let lastDistance = defaults?.integer(forKey: "complication.lastRunDistance")
        let todayCount = defaults?.integer(forKey: "complication.todayRunCount") ?? 0

        return SprintTimerEntry(
            date: Date(),
            lastRunTime: lastTime,
            lastRunDistance: lastDistance == 0 ? nil : lastDistance,
            todayRunCount: todayCount
        )
    }
}

struct SprintTimerComplicationView: View {
    var entry: SprintTimerEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryCorner:
            cornerView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        default:
            circularView
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: "figure.run")
                    .font(.system(size: 12))
                if let time = entry.lastRunTime {
                    Text(time)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.6)
                } else {
                    Text("\(entry.todayRunCount)")
                        .font(.system(size: 16, weight: .bold))
                }
            }
        }
    }

    private var cornerView: some View {
        ZStack {
            Text("\(entry.todayRunCount)")
                .font(.system(size: 20, weight: .bold))
        }
        .widgetLabel {
            Text("runs")
        }
    }

    private var rectangularView: some View {
        HStack {
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
            Spacer()
        }
    }

    private var inlineView: some View {
        if let time = entry.lastRunTime, let dist = entry.lastRunDistance {
            Text("\(dist)m \(time) | \(entry.todayRunCount) today")
        } else {
            Text("Sprint Timer: \(entry.todayRunCount) runs today")
        }
    }
}

struct SprintTimerWidget: Widget {
    let kind: String = "SprintTimerComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SprintTimerComplicationProvider()) { entry in
            SprintTimerComplicationView(entry: entry)
        }
        .configurationDisplayName("Sprint Timer")
        .description("Shows your last run time and today's run count.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}
