import SwiftUI
import SwiftData

struct iOSHistoryView: View {
    @Query(sort: \Run.date, order: .reverse) private var allRuns: [Run]
    @StateObject private var dailyNotesManager = DailyNotesManager.shared
    @State private var editMode: EditMode = .inactive
    @State private var selectedRuns = Set<UUID>()
    @State private var selectedDays = Set<Date>()
    @State private var activeEditor: ActiveEditor?

    private enum ActiveEditor: Identifiable {
        case runNotes(Run)
        case dayNotes(Date)
        case runTime(Run)

        var id: String {
            switch self {
            case .runNotes(let r): return "rn-\(r.id)"
            case .dayNotes(let d): return "dn-\(d.timeIntervalSince1970)"
            case .runTime(let r):  return "rt-\(r.id)"
            }
        }
    }
    @Environment(\.scenePhase) var scenePhase
    @State private var lastRefresh = Date()
    @State private var selectedDistance: Int = 0 // 0 = All runs
    @State private var expandedDays = Set<Date>()
    @State private var hasInitializedExpansion = false
    @State private var hasWeatherKey: Bool = WeatherService.shared.hasAPIKey

    // Get unique distances from runs
    var availableDistances: [Int] {
        let distances = Set(allRuns.map { $0.distance }).sorted()
        return distances
    }
    
    // Filter runs based on selected distance
    var filteredRuns: [Run] {
        if selectedDistance == 0 {
            return allRuns
        }
        return allRuns.filter { $0.distance == selectedDistance }
    }
    
    // Group runs by day, then by location within each day
    var runsByDay: [(date: Date, locationGroups: [(location: String, runs: [Run])])] {
        let grouped = Dictionary(grouping: filteredRuns) { run in
            Calendar.current.startOfDay(for: run.date)
        }
        return grouped.map { (date, runs) in
            // For runs missing a location, use the nearest known location from the same day
            // (they were likely at the same place)
            let knownLocations = runs.compactMap { $0.locationName }.filter { !$0.isEmpty }
            let locationGrouped = Dictionary(grouping: runs) { run in
                run.locationName ?? nearestLocation(for: run, from: runs) ?? knownLocations.first ?? "Unknown Location"
            }
            let sortedLocations = locationGrouped.map { (location: $0.key, runs: $0.value.sorted { $0.date > $1.date }) }
                .sorted { ($0.runs.first?.date ?? .distantPast) > ($1.runs.first?.date ?? .distantPast) }
            return (date: date, locationGroups: sortedLocations)
        }
        .sorted { $0.date > $1.date }
    }

    // Find the closest run (by time) that has a location name
    private func nearestLocation(for run: Run, from runs: [Run]) -> String? {
        runs.filter { $0.locationName != nil && !$0.locationName!.isEmpty }
            .min(by: { abs($0.date.timeIntervalSince(run.date)) < abs($1.date.timeIntervalSince(run.date)) })?
            .locationName
    }

    // Total run count for a day
    private func runCount(for day: (date: Date, locationGroups: [(location: String, runs: [Run])])) -> Int {
        day.locationGroups.reduce(0) { $0 + $1.runs.count }
    }

    // All runs for a day (flat)
    private func allRuns(for day: (date: Date, locationGroups: [(location: String, runs: [Run])])) -> [Run] {
        day.locationGroups.flatMap { $0.runs }
    }

    // MARK: - Stats for filtered distance

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        if minutes > 0 {
            return String(format: "%d:%02d.%03d", minutes, seconds, milliseconds)
        }
        return String(format: "%d.%03d", seconds, milliseconds)
    }

    private func averageTime(for runs: [Run]) -> String? {
        guard !runs.isEmpty else { return nil }
        let avg = runs.reduce(0) { $0 + $1.elapsedTime } / Double(runs.count)
        return formatTime(avg)
    }

    private func runsInWindow(days: Int) -> [Run] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return filteredRuns.filter { $0.date >= cutoff }
    }

    private var personalBest: Run? {
        filteredRuns.min(by: { $0.elapsedTime < $1.elapsedTime })
    }

    private var mostRecentDay: Date? {
        runsByDay.first?.date
    }

    private func isDayExpanded(_ date: Date) -> Bool {
        expandedDays.contains(date)
    }

    private func toggleDay(_ date: Date) {
        if expandedDays.contains(date) {
            expandedDays.remove(date)
        } else {
            expandedDays.insert(date)
        }
    }

    private func expandMostRecentIfNeeded() {
        if !hasInitializedExpansion, let most = mostRecentDay {
            expandedDays.insert(most)
            hasInitializedExpansion = true
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !hasWeatherKey {
                    weatherKeyPill
                }

                // Filter Picker
                HStack {
                    Text("Filter:")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    Picker("Distance", selection: $selectedDistance) {
                        Text("All Runs").tag(0)
                        ForEach(availableDistances, id: \.self) { distance in
                            Text("\(distance)m").tag(distance)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .accentColor(.blue)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemGroupedBackground))

                List {
                    // Stats section
                    Section {
                        if selectedDistance == 0 {
                            // All runs: just show total count
                            HStack {
                                Text("\(filteredRuns.count)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text("total runs")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            // Specific distance: show count + averages + PB
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("\(filteredRuns.count)")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Text("\(selectedDistance)m runs")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }

                                // Averages grid
                                let week = runsInWindow(days: 7)
                                let month = runsInWindow(days: 30)
                                let quarter = runsInWindow(days: 90)

                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 8) {
                                    StatCell(label: "Week", value: averageTime(for: week), count: week.count)
                                    StatCell(label: "Month", value: averageTime(for: month), count: month.count)
                                    StatCell(label: "3 Months", value: averageTime(for: quarter), count: quarter.count)
                                }

                                // Personal best
                                if let pb = personalBest {
                                    HStack(spacing: 6) {
                                        Image(systemName: "trophy.fill")
                                            .foregroundColor(.yellow)
                                            .font(.caption)
                                        Text("PB")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                        Text(pb.formattedTime)
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .fontDesign(.monospaced)
                                        Text(pb.date, style: .date)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    // Day sections (collapsed by default except most recent)
                    ForEach(runsByDay, id: \.date) { dayData in
                        Section(header: DayHeaderView(
                            date: dayData.date,
                            runCount: runCount(for: dayData),
                            isSelected: selectedDays.contains(dayData.date),
                            editMode: editMode,
                            hasDayNote: dailyNotesManager.hasNote(for: dayData.date),
                            isExpanded: isDayExpanded(dayData.date),
                            onToggle: {
                                toggleDaySelection(dayData.date, runs: allRuns(for: dayData))
                            },
                            onNotesTapped: {
                                activeEditor = .dayNotes(dayData.date)
                            },
                            onExpandToggle: {
                                toggleDay(dayData.date)
                            }
                        )) {
                            if isDayExpanded(dayData.date) {
                                ForEach(dayData.locationGroups, id: \.location) { locationGroup in
                                    LocationHeaderView(
                                        locationName: locationGroup.location,
                                        runs: locationGroup.runs
                                    )
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

                                    ForEach(locationGroup.runs) { run in
                                        RunRowView(
                                            run: run,
                                            isSelected: selectedRuns.contains(run.id),
                                            editMode: editMode,
                                            onToggle: {
                                                toggleRunSelection(run.id)
                                            },
                                            onNotesTapped: {
                                                activeEditor = .runNotes(run)
                                            }
                                        )
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                activeEditor = .runTime(run)
                                            } label: {
                                                Label("Edit Time", systemImage: "stopwatch")
                                            }
                                            .tint(.blue)
                                        }
                                    }
                                    .onDelete { indexSet in
                                        deleteRuns(at: indexSet, from: locationGroup.runs)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .refreshable {
                    await MainActor.run {
                        lastRefresh = Date()
                    }
                }
            }
            .navigationTitle("Sprint Timer")
            .onAppear {
                expandMostRecentIfNeeded()
                hasWeatherKey = WeatherService.shared.hasAPIKey
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WeatherAPIKeyChanged"))) { _ in
                hasWeatherKey = WeatherService.shared.hasAPIKey
            }
            .onChange(of: allRuns.count) { _, _ in
                expandMostRecentIfNeeded()
            }
            .onChange(of: selectedDistance) { _, _ in
                expandedDays.removeAll()
                hasInitializedExpansion = false
                expandMostRecentIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if editMode == .active {
                        Button("Delete Selected") {
                            deleteSelected()
                        }
                        .foregroundColor(.red)
                        .disabled(selectedRuns.isEmpty && selectedDays.isEmpty)
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .onChange(of: editMode) { oldValue, newValue in
                if newValue == .inactive {
                    selectedRuns.removeAll()
                    selectedDays.removeAll()
                }
            }
            .sheet(item: $activeEditor) { editor in
                switch editor {
                case .runNotes(let run): RunNoteEditorView(run: run)
                case .dayNotes(let date): DayNoteEditorView(date: date)
                case .runTime(let run): RunTimeEditorView(run: run)
                }
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                lastRefresh = Date()
                hasWeatherKey = WeatherService.shared.hasAPIKey
                // Request fresh data from Watch when app comes to foreground
                SyncManager.shared.requestFullSync()
            }
        }
    }

    private var weatherKeyPill: some View {
        Button {
            NotificationCenter.default.post(name: Notification.Name("SwitchToSettings"), object: nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Weather isn't being recorded")
                        .font(.subheadline.weight(.semibold))
                    Text("Tap to set up your free OpenWeather key")
                        .font(.caption2)
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .opacity(0.7)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.orange)
            .clipShape(Capsule())
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
    }

    private func toggleDaySelection(_ date: Date, runs: [Run]) {
        if selectedDays.contains(date) {
            selectedDays.remove(date)
            // Remove all runs from this day
            for run in runs {
                selectedRuns.remove(run.id)
            }
        } else {
            selectedDays.insert(date)
            // Add all runs from this day
            for run in runs {
                selectedRuns.insert(run.id)
            }
        }
    }
    
    private func toggleRunSelection(_ id: UUID) {
        if selectedRuns.contains(id) {
            selectedRuns.remove(id)
        } else {
            selectedRuns.insert(id)
        }
    }
    
    private func deleteSelected() {
        withAnimation {
            for run in allRuns where selectedRuns.contains(run.id) {
                DataManager.shared.deleteRun(run)
            }
            
            selectedRuns.removeAll()
            selectedDays.removeAll()
            editMode = .inactive
        }
    }
    
    private func deleteRuns(at offsets: IndexSet, from runs: [Run]) {
        withAnimation {
            for index in offsets {
                let run = runs[index]
                DataManager.shared.deleteRun(run)
            }
        }
    }
}

struct DayHeaderView: View {
    let date: Date
    let runCount: Int
    let isSelected: Bool
    let editMode: EditMode
    let hasDayNote: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onNotesTapped: () -> Void
    let onExpandToggle: () -> Void

    @StateObject private var dailyNotesManager = DailyNotesManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if editMode == .active {
                    Button(action: onToggle) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? .blue : .gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Button(action: onExpandToggle) {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 12)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(date, style: .date)
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("\(runCount) \(runCount == 1 ? "run" : "runs")")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(BorderlessButtonStyle())

                Spacer()

                Button(action: onNotesTapped) {
                    Image(systemName: hasDayNote ? "note.text" : "note.text.badge.plus")
                        .font(.system(size: 20))
                        .foregroundColor(hasDayNote ? .blue : .gray)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding(.vertical, 4)

            // Show day notes if they exist
            if hasDayNote {
                let dayNoteText = dailyNotesManager.getNote(for: date)
                if !dayNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "note.text")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.top, 1)

                        Text(dayNoteText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, editMode == .active ? 30 : 0)
                    .padding(.bottom, 4)
                }
            }
        }
    }
}

struct StatCell: View {
    let label: String
    let value: String?
    let count: Int

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            if let value {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .fontDesign(.monospaced)
            } else {
                Text("--")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Text("\(count) \(count == 1 ? "run" : "runs")")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct LocationHeaderView: View {
    let locationName: String
    let runs: [Run]

    // Use weather from the first run that has it
    private var weatherRun: Run? {
        runs.first { $0.weatherCondition != nil }
    }

    private var weatherIcon: String {
        switch weatherRun?.weatherCondition?.lowercased() {
        case "clear": return "sun.max.fill"
        case "clouds": return "cloud.fill"
        case "rain", "drizzle": return "cloud.rain.fill"
        case "thunderstorm": return "cloud.bolt.rain.fill"
        case "snow": return "cloud.snow.fill"
        case "mist", "fog", "haze": return "cloud.fog.fill"
        default: return "cloud.fill"
        }
    }

    private var tempString: String? {
        guard let temp = weatherRun?.temperature else { return nil }
        let fahrenheit = temp * 9.0 / 5.0 + 32.0
        return String(format: "%.0f°F", fahrenheit)
    }

    private var feelsLikeString: String? {
        guard let fl = weatherRun?.feelsLike else { return nil }
        let fahrenheit = fl * 9.0 / 5.0 + 32.0
        return String(format: "%.0f°F", fahrenheit)
    }

    private var altitudeString: String? {
        guard let alt = weatherRun?.altitude ?? runs.first(where: { $0.altitude != nil })?.altitude else { return nil }
        let feet = alt * 3.28084
        return String(format: "%.0f ft", feet)
    }

    // Icons for metric columns that appear in the run rows below this header.
    // Filtered to only the metrics actually present in this group's runs so we
    // don't show a legend marker for an unused column.
    private var metricLegend: [(icon: String, color: Color)] {
        var legend: [(String, Color)] = []
        if runs.contains(where: { ($0.actualDistance ?? 0) > 0 }) {
            legend.append(("location.fill", .blue))
        }
        if runs.contains(where: {
            $0.averageHeartRate != nil || $0.maxHeartRate != nil || $0.startHeartRate != nil || $0.endHeartRate != nil
        }) {
            legend.append(("heart.fill", .red))
        }
        if runs.contains(where: { ($0.steps ?? 0) > 0 }) {
            legend.append(("figure.walk", .green))
        }
        if runs.contains(where: { ($0.strideLength ?? 0) > 0 }) {
            legend.append(("ruler", .purple))
        }
        return legend
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Location name
            HStack(spacing: 4) {
                Text(locationName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }

            // Weather summary line
            if let condition = weatherRun?.weatherCondition, let temp = tempString {
                HStack(spacing: 4) {
                    Image(systemName: weatherIcon)
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("\(condition) \(temp)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let fl = feelsLikeString {
                        Text("(feels \(fl))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let humidity = weatherRun?.humidity {
                        Text("·")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Image(systemName: "humidity.fill")
                            .font(.caption2)
                            .foregroundColor(.cyan)
                        Text("\(Int(humidity))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let wind = weatherRun?.windSpeed {
                        Text("·")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Image(systemName: "wind")
                            .font(.caption2)
                            .foregroundColor(.teal)
                        Text(String(format: "%.0f mph", wind * 2.237))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Secondary details row
            HStack(spacing: 12) {
                if let alt = altitudeString {
                    HStack(spacing: 2) {
                        Image(systemName: "mountain.2.fill")
                            .font(.caption2)
                            .foregroundColor(.brown)
                        Text(alt)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if let aqi = weatherRun?.aqi {
                    HStack(spacing: 2) {
                        Image(systemName: "aqi.medium")
                            .font(.caption2)
                            .foregroundColor(aqi <= 2 ? .green : aqi <= 3 ? .yellow : .red)
                        Text("AQI \(aqi)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if let uv = weatherRun?.uvIndex, uv > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "sun.max.trianglebadge.exclamationmark.fill")
                            .font(.caption2)
                            .foregroundColor(uv <= 2 ? .green : uv <= 5 ? .yellow : .red)
                        Text("UV \(uv)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Column legend for the run rows below — colors match the values in the rows.
            if !metricLegend.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    ForEach(metricLegend.indices, id: \.self) { i in
                        Image(systemName: metricLegend[i].icon)
                            .font(.caption2)
                            .foregroundColor(metricLegend[i].color)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RunRowView: View {
    let run: Run
    let isSelected: Bool
    let editMode: EditMode
    let onToggle: () -> Void
    let onNotesTapped: () -> Void
    
    private var hasRunNotes: Bool {
        !run.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if editMode == .active {
                    Button(action: onToggle) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? .blue : .gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(run.distance)m")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Text(run.formattedTime)
                            .font(.headline)
                            .fontDesign(.monospaced)
                    }
                    
                    // Icons appear as a legend in the LocationHeaderView above; values here
                    // stay color-coded to the same palette so each number identifies itself.
                    HStack(spacing: 10) {
                        Text(run.date, style: .time)
                            .font(.caption)
                            .foregroundColor(.gray)

                        if let gpsDistance = run.actualDistance, gpsDistance > 0 {
                            Text("\(Int(gpsDistance))m")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }

                        if let avg = run.averageHeartRate {
                            HStack(spacing: 0) {
                                Text("\(Int(avg))")
                                if let max = run.maxHeartRate {
                                    Text("/\(Int(max))").opacity(0.7)
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        } else if let end = run.endHeartRate {
                            Text("\(Int(end))")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else if let start = run.startHeartRate {
                            Text("\(Int(start))")
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        if let steps = run.steps, steps > 0 {
                            Text("\(steps)")
                                .font(.caption)
                                .foregroundColor(.green)
                        }

                        if let stride = run.strideLength, stride > 0 {
                            Text(String(format: "%.1fm", stride))
                                .font(.caption)
                                .foregroundColor(.purple)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(run.pace)
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Button(action: onNotesTapped) {
                        Image(systemName: hasRunNotes ? "note.text" : "note.text.badge.plus")
                            .font(.system(size: 20)) // Fixed size for consistency
                            .foregroundColor(hasRunNotes ? .blue : .gray)
                            .frame(width: 30, height: 30) // Fixed frame
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.vertical, 4)
            
            // Show run notes if they exist
            if hasRunNotes {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.top, 1)
                    
                    Text(run.notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, editMode == .active ? 30 : 0)
                .padding(.bottom, 4)
            }
        }
    }
}

struct RunNoteEditorView: View {
    let run: Run
    @Environment(\.dismiss) private var dismiss
    @State private var noteText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Run Details")) {
                    HStack {
                        Text("Distance:")
                        Spacer()
                        Text("\(run.distance)m")
                    }
                    HStack {
                        Text("Time:")
                        Spacer()
                        Text(run.formattedTime)
                    }
                    HStack {
                        Text("Date:")
                        Spacer()
                        Text(run.formattedDate)
                    }
                }
                
                Section(header: Text("Notes")) {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 100)
                        .focused($isTextFieldFocused)
                        .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Run Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveNotes()
                    }
                    .fontWeight(.medium)
                }
            }
            .onAppear {
                noteText = run.notes
                
                // Focus the text field after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isTextFieldFocused = true
                }
            }
        }
    }
    
    private func saveNotes() {
        run.notes = noteText
        
        do {
            try DataManager.shared.modelContainer.mainContext.save()
            dismiss()
        } catch {
            // Note save failed
        }
    }
}

struct DayNoteEditorView: View {
    let date: Date
    @Environment(\.dismiss) private var dismiss
    @StateObject private var dailyNotesManager = DailyNotesManager.shared
    @State private var noteText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Day Details")) {
                    HStack {
                        Text("Date:")
                        Spacer()
                        Text(date, style: .date)
                    }
                }
                
                Section(header: Text("Day Notes")) {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 100)
                        .focused($isTextFieldFocused)
                        .scrollContentBackground(.hidden)
                }
                
                Section {
                    Text("Day notes are separate from individual run notes")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Day Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveDayNotes()
                    }
                    .fontWeight(.medium)
                }
            }
            .onAppear {
                noteText = dailyNotesManager.getNote(for: date)
                
                // Focus the text field after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isTextFieldFocused = true
                }
            }
        }
    }
    
    private func saveDayNotes() {
        dailyNotesManager.setNote(noteText, for: date)
        dismiss()
    }
}

struct RunTimeEditorView: View {
    let run: Run
    @Environment(\.dismiss) private var dismiss
    @State private var timeText = ""
    @State private var errorMessage: String?
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Run Details")) {
                    HStack {
                        Text("Distance:")
                        Spacer()
                        Text("\(run.distance)m")
                    }
                    HStack {
                        Text("Date:")
                        Spacer()
                        Text(run.formattedDate)
                    }
                    HStack {
                        Text("Original time:")
                        Spacer()
                        Text(run.formattedTime)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("New Time"), footer: Text("Format: 12.345 or 1:23.456")) {
                    TextField("Time", text: $timeText)
                        .keyboardType(.decimalPad)
                        .focused($isTextFieldFocused)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Edit Run Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveTime()
                    }
                    .fontWeight(.medium)
                    .disabled(parsedInterval(from: timeText) == nil)
                }
            }
            .onAppear {
                timeText = run.formattedTime
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isTextFieldFocused = true
                }
            }
        }
    }

    private func parsedInterval(from text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Accept "M:SS.mmm" or "S.mmm" / "SS.mmm"
        let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            guard let seconds = Double(parts[0]), seconds >= 0 else { return nil }
            return seconds
        case 2:
            guard let minutes = Int(parts[0]), minutes >= 0,
                  let seconds = Double(parts[1]), seconds >= 0, seconds < 60
            else { return nil }
            return TimeInterval(minutes) * 60 + seconds
        default:
            return nil
        }
    }

    private func saveTime() {
        guard let newInterval = parsedInterval(from: timeText) else {
            errorMessage = "Enter a valid time like 12.345 or 1:23.456"
            return
        }
        run.elapsedTime = newInterval
        do {
            try DataManager.shared.modelContainer.mainContext.save()
            // Push to watch via the existing upsert path (handleRunAdded updates by ID).
            let syncData = SyncManager.shared.runToSyncData(run)
            SyncManager.shared.syncNewRun(syncData)
            dismiss()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}
