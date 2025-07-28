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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateFormatter.string(from: date))
                    .font(.system(size: 14, weight: .medium))
                
                Text("\(runs.count) runs")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Day notes icon
            Image(systemName: hasDayNotes ? "note.text" : "note.text")
                .font(.system(size: 18))
                .foregroundColor(hasDayNotes ? .blue : .gray)
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
        VStack {
            // Header with X button moved higher
            HStack {
                Button(action: onBack) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                HStack(spacing: 6) {
                    Text(dateFormatter.string(from: date))
                        .font(.system(size: 14, weight: .medium))
                    
                    // Day notes icon
                    Image(systemName: hasDayNotes ? "note.text" : "note.text")
                        .font(.system(size: 18))
                        .foregroundColor(hasDayNotes ? .blue : .gray)
                }
                
                Spacer()
                
                // Invisible spacer to balance
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .opacity(0)
            }
            .padding(.horizontal)
            .padding(.top, 5)
            
            // Stats
            HStack(spacing: 40) {
                VStack(spacing: 1) {
                    Text("\(runs.count)")
                        .font(.system(size: 36, weight: .bold))
                    Text("Runs")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                
                VStack(spacing: 1) {
                    Text(averageTime)
                        .font(.system(size: 36, weight: .bold))
                    Text("Avg")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
            }
            .padding(.vertical, 8)
            
            // Runs list with notes icons
            List {
                ForEach(runs) { run in
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
                    .padding(.vertical, 6)
                }
                .onDelete(perform: deleteRuns)
            }
            .listStyle(CarouselListStyle())
        }
        .navigationBarHidden(true)  // Hide the default navigation bar
    }
    
    private func deleteRuns(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                DataManager.shared.deleteRun(runs[index])
            }
        }
    }
}
