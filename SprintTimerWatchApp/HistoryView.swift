import SwiftUI
import SwiftData
import WatchKit

struct HistoryView: View {
    @Query(sort: \Run.date, order: .reverse) private var runs: [Run]
    @Environment(\.dismiss) var dismiss
    @State private var selectedDate: Date?
    @State private var pendingRestore: Any? = nil
    @StateObject private var dailyNotesManager = DailyNotesManager.shared
    
    // Sheet presentation states for notes editing
    @State private var showingDayNotes = false
    @State private var showingRunNotes = false
    @State private var editingDate: Date?
    @State private var editingRun: Run?
    @StateObject private var notesViewModel = SprintTimerViewModel()
    @State private var selectedDistance: Int = 0 // 0 = All runs
    
    // Group runs by day
    var runsByDay: [Date: [Run]] {
        Dictionary(grouping: filteredRuns) { run in
            Calendar.current.startOfDay(for: run.date)
        }
    }
    
    // Get sorted days
    var sortedDays: [Date] {
        runsByDay.keys.sorted(by: >)
    }
    
    // Unique distances available for filtering
    var availableDistances: [Int] {
        let distances = Set(runs.map { $0.distance }).sorted()
        return distances
    }

    // Filtered runs based on selected distance
    var filteredRuns: [Run] {
        if selectedDistance == 0 { return runs }
        return runs.filter { $0.distance == selectedDistance }
    }
    
    var body: some View {
        NavigationView {
            if selectedDate == nil {
                // Day Selection View
                VStack {
                    Text("History")
                        .font(.system(size: 18, weight: .bold))
                        .padding(.vertical, 8)
                    
                    // Distance Filter Picker (watchOS)
                    HStack(spacing: 6) {
                        Text("Filter:")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)

                        Picker("Distance", selection: $selectedDistance) {
                            Text("All").tag(0)
                            ForEach(availableDistances, id: \.self) { distance in
                                Text("\(distance)m").tag(distance)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                    
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
                    onBack: { selectedDate = nil },
                    showingDayNotes: $showingDayNotes,
                    showingRunNotes: $showingRunNotes,
                    editingDate: $editingDate,
                    editingRun: $editingRun,
                    notesViewModel: notesViewModel
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RestoreHistoryContext"))) { notification in
            // Restore exact context: if we get a Date, open that day; if we get a Run, open its day
            if let date = notification.object as? Date {
                selectedDate = Calendar.current.startOfDay(for: date)
            } else if let run = notification.object as? Run {
                selectedDate = Calendar.current.startOfDay(for: run.date)
            }
        }
        .sheet(isPresented: $showingDayNotes) {
            DayNotesView(viewModel: notesViewModel)
        }
        .sheet(isPresented: $showingRunNotes) {
            NotesView(viewModel: notesViewModel)
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
                Image(systemName: "note.text")
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
    
    // Sheet presentation bindings passed from parent
    @Binding var showingDayNotes: Bool
    @Binding var showingRunNotes: Bool
    @Binding var editingDate: Date?
    @Binding var editingRun: Run?
    let notesViewModel: SprintTimerViewModel
    
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
            
            // Date with notes icon - make entire area tappable for day notes
            Button(action: {
                editingDate = date
                notesViewModel.currentEditingDate = date
                showingDayNotes = true
            }) {
                HStack(spacing: 6) {
                    Text(dateFormatter.string(from: date))
                        .font(.system(size: 18, weight: .semibold))  // Bigger font
                    
                    // Day notes icon - simple note icon, blue if has notes, gray if not
                    Image(systemName: "note.text")
                        .font(.system(size: 16))
                        .foregroundColor(hasDayNotes ? .blue : .gray)
                }
                .contentShape(Rectangle()) // Make entire area tappable
                .frame(maxWidth: .infinity, alignment: .center) // Center the date and icon
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal)
            .padding(.top, -20)  // Move date up behind clock
            
            // Stats - repositioned and improved spacing
            HStack(spacing: 0) {  // No spacing, we'll control positioning manually
                // Left side - "Runs" flush to edge
                HStack(spacing: 0.5) {  // Minimal space between "Runs" and count
                    Text("Runs")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .rotationEffect(.degrees(-90))
                        .fixedSize() // Prevent truncation
                    Text("\(runs.count)")
                        .font(.system(size: 36, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                }
                
                Spacer() // Fill the space between left and right
                
                // Right side - "Avg" flush to right edge
                HStack(spacing: 1.5) {  
                    Text("Avg")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .rotationEffect(.degrees(-90))
                        .fixedSize() // Prevent truncation instead of using frame
                    Text(averageTime)
                        .font(.system(size: 36, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                }
            }
            .padding(.leading, -8)  // Keep left side where it is (perfect)
            .padding(.trailing, 0)  // No negative padding on right to prevent cutoff
            .padding(.vertical, 4)
            
            // Day note preview under stats (one line, tappable to edit)
            if hasDayNotes {
                let dayNoteText = dailyNotesManager.getNote(for: date).trimmingCharacters(in: .whitespacesAndNewlines)
                if !dayNoteText.isEmpty {
                    Button(action: { 
                        editingDate = date
                        notesViewModel.currentEditingDate = date
                        showingDayNotes = true
                    }) {
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
                        editingRun = run
                        notesViewModel.currentRunNotes = run.notes
                        notesViewModel.currentEditingRun = run
                        showingRunNotes = true
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(run.distance)m")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                                
                                Spacer()
                                
                                // Make the time + icon area more prominent and tappable
                                HStack(spacing: 8) {
                                    Text(run.formattedTime)
                                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                    
                                    // Run notes icon - simple note icon, blue if has notes, gray if not
                                    Image(systemName: "note.text")
                                        .font(.system(size: 18))
                                        .foregroundColor(run.notes.isEmpty ? .gray : .blue)
                                }
                            }
                            
                            // Show run notes if they exist - also tappable
                            if !run.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button(action: {
                                    editingRun = run
                                    notesViewModel.currentRunNotes = run.notes
                                    notesViewModel.currentEditingRun = run
                                    showingRunNotes = true
                                }) {
                                    HStack(alignment: .top, spacing: 4) {
                                        Image(systemName: "note.text")
                                            .font(.system(size: 10))
                                            .foregroundColor(.blue)
                                            .padding(.top, 1)
                                        
                                        Text(run.notes)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle()) // Ensure entire row is tappable
                        .padding(.vertical, 8) // Increase hit target area
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.vertical, 2) // Reduce outer padding to compensate
                }
                .onDelete(perform: deleteRuns)
            }
            .listStyle(CarouselListStyle())
            .padding(.top, 8)
        }
        .navigationBarHidden(true)  // Hide the default navigation bar
    }
    
    private func deleteRuns(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                DataManager.shared.modelContainer.mainContext.delete(runs[index])
            }
            try? DataManager.shared.modelContainer.mainContext.save()
        }
    }
}

