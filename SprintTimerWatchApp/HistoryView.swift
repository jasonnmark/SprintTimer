import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \Run.date, order: .reverse) private var runs: [Run]
    @Environment(\.dismiss) var dismiss
    @State private var selectedDate: Date?
    @StateObject private var dailyNotesManager = DailyNotesManager.shared
    
    // Group runs by day
    var runsByDay: [Date: [Run]] {
        Dictionary(grouping: runs) { run in
            Calendar.current.startOfDay(for: run.date)
        }
    }
    
    // Get sorted days
    var sortedDays: [Date] {
        runsByDay.keys.sorted(by: >)
    }
    
    var body: some View {
        NavigationView {
            if selectedDate == nil {
                // Day Selection View
                VStack {
                    Text("History")
                        .font(.system(size: 18, weight: .bold))
                        .padding(.vertical, 8)
                    
                    if sortedDays.isEmpty {
                        Spacer()
                        VStack(spacing: 5) {
                            Image(systemName: "figure.run")
                                .font(.system(size: 30))
                                .foregroundColor(.gray)
                            Text("No runs yet")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                            Text("Complete your first sprint!")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    } else {
                        List(sortedDays, id: \.self) { day in
                            Button(action: {
                                selectedDate = day
                            }) {
                                DayRow(date: day, runs: runsByDay[day] ?? [])
                                    .frame(maxWidth: .infinity, alignment: .leading) // Make button fill entire row width
                                    .contentShape(Rectangle()) // Make entire area tappable
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .listStyle(CarouselListStyle())
                    }
                }
                .onAppear {
                    print("Watch History: \(runs.count) runs loaded")
                }
            } else {
                // Day Detail View
                DayDetailView(
                    date: selectedDate!,
                    runs: runsByDay[selectedDate!] ?? [],
                    onBack: { selectedDate = nil }
                )
            }
        }
    }
}

// Row for each day in the list
struct DayRow: View {
    let date: Date
    let runs: [Run]
    @StateObject private var dailyNotesManager = DailyNotesManager.shared
    
    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "E M/d"  // "Sun 7/27" format
        return formatter
    }
    
    var hasDayNotes: Bool {
        dailyNotesManager.hasNote(for: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateFormatter.string(from: date))
                        .font(.system(size: 14, weight: .medium))
                    
                    Text("\(runs.count) runs")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Notes icon
                Image(systemName: hasDayNotes ? "note.text" : "note.text")
                    .font(.system(size: 16))
                    .foregroundColor(hasDayNotes ? .blue : .gray)
            }
            
            // Show day notes if they exist
            if hasDayNotes {
                let dayNoteText = dailyNotesManager.getNote(for: date)
                if !dayNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                            .padding(.top, 1)
                        
                        Text(dayNoteText)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// Detail view for a specific day
struct DayDetailView: View {
    let date: Date
    let runs: [Run]
    let onBack: () -> Void
    @StateObject private var dailyNotesManager = DailyNotesManager.shared
    @State private var selectedRun: Run?
    @State private var activeSheet: ActiveSheet?
    
    enum ActiveSheet: Identifiable {
        case run(Run)
        case day(Date)
        
        var id: String {
            switch self {
            case .run(let run):
                return "run-\(run.id.uuidString)"
            case .day(let date):
                return "day-\(date.timeIntervalSince1970)"
            }
        }
    }
    
    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "E M/d"  // "Sun 7/27" format
        return formatter
    }
    
    var hasDayNotes: Bool {
        dailyNotesManager.hasNote(for: date)
    }
    
    var averageTime: String {
        guard !runs.isEmpty else { return "0.000" }
        let totalTime = runs.reduce(0) { $0 + $1.elapsedTime }
        let avgTime = totalTime / Double(runs.count)
        
        let minutes = Int(avgTime) / 60
        let seconds = Int(avgTime) % 60
        let milliseconds = Int((avgTime.truncatingRemainder(dividingBy: 1)) * 1000)
        
        if minutes > 0 {
            return String(format: "%d:%02d.%03d", minutes, seconds, milliseconds)
        } else {
            return String(format: "%d.%03d", seconds, milliseconds)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with X button at top of screen
            HStack {
                Button(action: onBack) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, -45)  // Move X up to be level with clock
            
            // Date with notes icon - make tappable for day notes
            Button(action: {
                activeSheet = .day(date)
            }) {
                HStack(spacing: 6) {
                    Text(dateFormatter.string(from: date))
                        .font(.system(size: 18, weight: .semibold))  // Bigger font
                    
                    // Day notes icon
                    Image(systemName: hasDayNotes ? "note.text" : "note.text")
                        .font(.system(size: 18))
                        .foregroundColor(hasDayNotes ? .blue : .gray)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, -20)  // Move date up behind clock
            
            // Stats
            HStack(spacing: 18) {
                HStack(spacing: 3) {
                    Text("Runs")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .rotationEffect(.degrees(-90))
                    Text("\(runs.count)")
                        .font(.system(size: 36, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                }
                
                HStack(spacing: 3) {
                    Text("Avg")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .rotationEffect(.degrees(-90))
                    Text(averageTime)
                        .font(.system(size: 36, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 4)
            
            // Day note preview under stats (one line, tappable to edit)
            if hasDayNotes {
                let dayNoteText = dailyNotesManager.getNote(for: date).trimmingCharacters(in: .whitespacesAndNewlines)
                if !dayNoteText.isEmpty {
                    Button(action: { activeSheet = .day(date) }) {
                        HStack(alignment: .center, spacing: 6) {
                            Image(systemName: "note.text")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                            Text(dayNoteText)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal)
                    .padding(.top, 4)
                }
            }
            
            // Runs list with notes - make entire rows tappable
            List {
                ForEach(runs) { run in
                    Button(action: {
                        selectedRun = run
                        activeSheet = .run(run)
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(run.distance)m")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                                
                                Spacer()
                                
                                Text(run.formattedTime)
                                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                
                                // Run notes icon
                                Image(systemName: run.notes.isEmpty ? "note.text" : "note.text")
                                    .font(.system(size: 18))
                                    .foregroundColor(run.notes.isEmpty ? .gray : .blue)
                            }
                            
                            // Show run notes if they exist
                            if !run.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                HStack(alignment: .top, spacing: 4) {
                                    Image(systemName: "note.text")
                                        .font(.system(size: 10))
                                        .foregroundColor(.blue)
                                        .padding(.top, 1)
                                    
                                    Text(run.notes)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.vertical, 6)
                }
                .onDelete(perform: deleteRuns)
            }
            .listStyle(CarouselListStyle())
            .padding(.top, 8)
        }
        .navigationBarHidden(true)  // Hide the default navigation bar
        .sheet(item: $activeSheet) { item in
            switch item {
            case .run(let run):
                WatchRunNotesView(run: run)
            case .day(let date):
                WatchDayNotesView(date: date)
            }
        }
    }
    
    private func deleteRuns(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                DataManager.shared.deleteRun(runs[index])
            }
        }
    }
}

// Watch-specific Run Notes View
struct WatchRunNotesView: View {
    let run: Run
    @Environment(\.dismiss) private var dismiss
    @State private var noteText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 8) {
                Text("Run Notes")
                    .font(.system(size: 14, weight: .bold))
                
                Text("\(run.distance)m - \(run.formattedTime)")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                
                TextField("Add run notes...", text: $noteText, axis: .vertical)
                    .font(.system(size: 12))
                    .focused($isTextFieldFocused)
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    .padding(.horizontal)
                
                HStack(spacing: 12) {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Cancel")
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        saveRunNotes()
                    }) {
                        Text("Save")
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
        }
        .onAppear {
            noteText = run.notes
            
            // Focus the text field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
    }
    
    private func saveRunNotes() {
        run.notes = noteText
        
        do {
            try DataManager.shared.modelContainer.mainContext.save()
            dismiss()
        } catch {
            print("Error saving run notes: \(error)")
        }
    }
}

// Watch-specific Day Notes View  
struct WatchDayNotesView: View {
    let date: Date
    @Environment(\.dismiss) private var dismiss
    @StateObject private var dailyNotesManager = DailyNotesManager.shared
    @State private var noteText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 8) {
                Text("Day Notes")
                    .font(.system(size: 14, weight: .bold))
                
                Text(date, style: .date)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                
                TextField("Add day notes...", text: $noteText, axis: .vertical)
                    .font(.system(size: 12))
                    .focused($isTextFieldFocused)
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    .padding(.horizontal)
                
                HStack(spacing: 12) {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Cancel")
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        saveDayNotes()
                    }) {
                        Text("Save")
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
        }
        .onAppear {
            noteText = dailyNotesManager.getNote(for: date)
            
            // Focus the text field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
    }
    
    private func saveDayNotes() {
        dailyNotesManager.setNote(noteText, for: date)
        dismiss()
    }
}

