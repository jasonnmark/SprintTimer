import WidgetKit
import SwiftUI

@main
struct SprintTimerComplicationBundle: WidgetBundle {
    var body: some Widget {
        SprintTimerLauncherWidget()
        SprintTimerStatsWidget()
    }
}
