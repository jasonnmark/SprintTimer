import SwiftUI
import SwiftData

struct iOSHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Run.date, order: .reverse) private var runs: [Run]
    @State private var editMode: EditMode = .inactive
    @State private var selectedRuns = Set<UUID>()
    @State private var selectedDays = Set<Date>()
    @State private var showingNoteEditor = false
    @State private var noteType: NoteType = .run
    @State private var selectedItem: Any?
    
    enum NoteType {
        case run, day
    }
    
    // Group runs by day
    var runsByDay: [(date: Date, runs: [Run])] {
        let grouped = Dictionary(grouping: runs) { run in
            Calendar.current.startOfDay(for: run.date)
        }
        return grouped.map { (date: $0.key, runs: $0.value) }
            .sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(runsByDay, id: \.date) { dayData in
                    Section(header: DayHeaderView(
                        date: dayData.date,
                        runCount: dayData.runs.count,
                        isSelected: selectedDays.contains(dayData.date),
                        editMode: editMode,
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
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
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
            .onChange(of: editMode) { newValue in
                if newValue == .inactive {
                    selectedRuns.removeAll()
                    selectedDays.removeAll()
                }
            }
            .sheet(isPresented: $showingNoteEditor) {
                if noteType == .run, let run = selectedItem as? Run {
                    RunNoteEditorView(run: run)
                } else if noteType == .day, let date = selectedItem as? Date {
                    DayNoteEditorView(date: date, runs: runs.filter {
                        Calendar.current.isDate($0.date, inSameDayAs: date)
                    })
                }
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
            for run in runs where selectedRuns.contains(run.id) {
                modelContext.delete(run)
            }
            
            do {
                try modelContext.save()
            } catch {
                print("Error deleting runs: \(error)")
            }
            
            selectedRuns.removeAll()
            selectedDays.removeAll()
            editMode = .inactive
        }
    }
}

struct DayHeaderView: View {
    let date: Date
    let runCount: Int
    let isSelected: Bool
    let editMode: EditMode
    let onToggle: () -> Void
    let onNotesTapped: () -> Void
    
    @Query private var runs: [Run]
    
    private var dayNotes: String? {
        // Check if any run from this day has day notes
        let dayRuns = runs.filter {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }
        
        // Look for day notes in run notes (before the | separator)
        for run in dayRuns {
            let components = run.notes.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if components.count > 0 && !components[0].isEmpty {
                return components[0]
            }
        }
        return nil
    }
    
    var body: some View {
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
                Image(systemName: dayNotes != nil ? "note.text" : "note.text.badge.plus")
                    .foregroundColor(dayNotes != nil ? .blue : .gray)
            }
            .buttonStyle(PlainButtonStyle())
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
    
    private var runSpecificNotes: String? {
        let components = run.notes.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        if components.count > 1 && !components[1].isEmpty {
            return components[1]
        } else if components.count == 1 && !components[0].isEmpty {
            // If there's only one component, it might be run-specific notes
            return components[0]
        }
        return nil
    }
    
    var body: some View {
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
                    Image(systemName: runSpecificNotes != nil ? "note.text" : "note.text.badge.plus")
                        .foregroundColor(runSpecificNotes != nil ? .blue : .gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }
}

struct RunNoteEditorView: View {
    let run: Run
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var noteText = ""
    
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
                }
            }
            .navigationTitle("Run Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveNotes()
                    }
                }
            }
            .onAppear {
                // Extract run-specific notes
                let components = run.notes.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if components.count > 1 {
                    noteText = components[1]
                } else if components.count == 1 {
                    noteText = components[0]
                }
            }
        }
    }
    
    private func saveNotes() {
        // Preserve day notes if they exist
        let components = run.notes.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        let dayNotes = components.count > 0 ? components[0] : ""
        
        if !dayNotes.isEmpty && !noteText.isEmpty {
            run.notes = "\(dayNotes) | \(noteText)"
        } else if !noteText.isEmpty {
            run.notes = noteText
        } else {
            run.notes = dayNotes
        }
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving notes: \(error)")
        }
    }
}

struct DayNoteEditorView: View {
    let date: Date
    let runs: [Run]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var noteText = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Day Details")) {
                    HStack {
                        Text("Date:")
                        Spacer()
                        Text(date, style: .date)
                    }
                    HStack {
                        Text("Total Runs:")
                        Spacer()
                        Text("\(runs.count)")
                    }
                }
                
                Section(header: Text("Day Notes")) {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 100)
                }
                
                Section {
                    Text("These notes will be applied to all runs on this day")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Day Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveDayNotes()
                    }
                }
            }
            .onAppear {
                // Load existing day notes if any
                if let firstRun = runs.first {
                    let components = firstRun.notes.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    if components.count > 0 {
                        noteText = components[0]
                    }
                }
            }
        }
    }
    
    private func saveDayNotes() {
        // Update all runs for this day
        for run in runs {
            let components = run.notes.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            let runNotes = components.count > 1 ? components[1] : ""
            
            if !noteText.isEmpty && !runNotes.isEmpty {
                run.notes = "\(noteText) | \(runNotes)"
            } else if !noteText.isEmpty {
                run.notes = noteText
            } else {
                run.notes = runNotes
            }
        }
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving day notes: \(error)")
        }
    }
}
