import SwiftUI
import SwiftData

struct iOSHistoryView: View {
    @Query(sort: \Run.date, order: .reverse) private var allRuns: [Run]
    @StateObject private var dailyNotesManager = DailyNotesManager.shared
    @State private var editMode: EditMode = .inactive
    @State private var selectedRuns = Set<UUID>()
    @State private var selectedDays = Set<Date>()
    @State private var showingNoteEditor = false
    @State private var noteType: NoteType = .run
    @State private var selectedItem: Any?
    @Environment(\.scenePhase) var scenePhase
    @State private var lastRefresh = Date()
    @State private var selectedDistance: Int = 0 // 0 = All runs
    
    enum NoteType {
        case run, day
    }
    
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
    
    // Group runs by day
    var runsByDay: [(date: Date, runs: [Run])] {
        let grouped = Dictionary(grouping: filteredRuns) { run in
            Calendar.current.startOfDay(for: run.date)
        }
        return grouped.map { (date: $0.key, runs: $0.value) }
            .sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
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
                    ForEach(runsByDay, id: \.date) { dayData in
                        Section(header: DayHeaderView(
                            date: dayData.date,
                            runCount: dayData.runs.count,
                            isSelected: selectedDays.contains(dayData.date),
                            editMode: editMode,
                            hasDayNote: dailyNotesManager.hasNote(for: dayData.date),
                            onToggle: {
                                toggleDaySelection(dayData.date, runs: dayData.runs)
                            },
                            onNotesTapped: {
                                noteType = .day
                                selectedItem = dayData.date
                                showingNoteEditor = true
                            }
                        )) {
                            ForEach(dayData.runs) { run in
                                RunRowView(
                                    run: run,
                                    isSelected: selectedRuns.contains(run.id),
                                    editMode: editMode,
                                    onToggle: {
                                        toggleRunSelection(run.id)
                                    },
                                    onNotesTapped: {
                                        noteType = .run
                                        selectedItem = run
                                        showingNoteEditor = true
                                    }
                                )
                            }
                            .onDelete { indexSet in
                                deleteRuns(at: indexSet, from: dayData.runs)
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .refreshable {
                    // Force UI refresh without creating bindings that cause performance issues
                    await MainActor.run {
                        lastRefresh = Date()
                    }
                }
            }
            .navigationTitle("History")
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
            .sheet(isPresented: $showingNoteEditor) {
                if noteType == .run, let run = selectedItem as? Run {
                    RunNoteEditorView(run: run)
                } else if noteType == .day, let date = selectedItem as? Date {
                    DayNoteEditorView(date: date)
                }
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                // Force a refresh when app becomes active
                lastRefresh = Date()
                print("History view refreshing...")
            }
        }
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
    let onToggle: () -> Void
    let onNotesTapped: () -> Void
    
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
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(date, style: .date)
                        .font(.headline)
                    Text("\(runCount) runs")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Button(action: onNotesTapped) {
                    Image(systemName: hasDayNote ? "note.text" : "note.text.badge.plus")
                        .font(.system(size: 20)) // Fixed size for consistency
                        .foregroundColor(hasDayNote ? .blue : .gray)
                        .frame(width: 30, height: 30) // Fixed frame
                }
                .buttonStyle(PlainButtonStyle())
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
                    
                    HStack(spacing: 12) {
                        Text(run.date, style: .time)
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        if let gpsDistance = run.actualDistance, gpsDistance > 0 {
                            Label("\(Int(gpsDistance))m", systemImage: "location.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        
                        if let heartRate = run.endHeartRate {
                            Label("\(Int(heartRate))", systemImage: "heart.fill")
                                .font(.caption)
                                .foregroundColor(.red)
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
        NavigationView {
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
            print("Error saving notes: \(error)")
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
        NavigationView {
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
