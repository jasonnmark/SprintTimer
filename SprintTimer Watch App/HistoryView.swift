import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Run.date, order: .reverse) private var runs: [Run]
    @Environment(\.dismiss) var dismiss
    @State private var selectedDate: Date?
    
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
    
    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dateFormatter.string(from: date))
                .font(.system(size: 14, weight: .medium))
            
            Text("\(runs.count) runs")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }
}

// Detail view for a specific day
struct DayDetailView: View {
    let date: Date
    let runs: [Run]
    let onBack: () -> Void
    @Environment(\.modelContext) private var modelContext
    
    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
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
            // Header with date
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Text(dateFormatter.string(from: date))
                    .font(.system(size: 14, weight: .medium))
                
                Spacer()
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
            
            // Runs list
            List {
                ForEach(runs) { run in
                    HStack {
                        Text("\(run.distance)m")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        
                        Spacer()
                        
                        Text(run.formattedTime)
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 6)
                }
                .onDelete(perform: deleteRuns)
            }
            .listStyle(CarouselListStyle())
        }
    }
    
    private func deleteRuns(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(runs[index])
            }
        }
    }
}

// Simplified Stats View
struct StatsView: View {
    @Query private var runs: [Run]
    
    var totalRuns: Int {
        runs.count
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
        HStack(spacing: 40) {
            VStack(spacing: 2) {
                Text("\(totalRuns)")
                    .font(.system(size: 24, weight: .bold))
                Text("Total Runs")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            
            VStack(spacing: 2) {
                Text(averageTime)
                    .font(.system(size: 24, weight: .bold))
                Text("Average")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 10)
    }
}
