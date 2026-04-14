import SwiftUI
import SwiftData

struct iOSContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            iOSHistoryView()
                .tabItem {
                    Label("History", systemImage: "figure.run")
                }
                .tag(0)

            iOSSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(1)

            iOSExportView()
                .tabItem {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .tag(2)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToSettings"))) { _ in
            selectedTab = 1
        }
    }
}

// Simple home view without custom run types
struct SimpleHomeView: View {
    @Query(sort: \Run.date, order: .reverse) private var runs: [Run]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Stats summary
                VStack(spacing: 10) {
                    Text("Sprint Timer")
                        .font(.largeTitle)
                        .bold()
                    
                    if !runs.isEmpty {
                        HStack(spacing: 40) {
                            VStack {
                                Text("\(runs.count)")
                                    .font(.title)
                                    .bold()
                                Text("Total Runs")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            VStack {
                                Text(averageTime)
                                    .font(.title)
                                    .bold()
                                Text("Average Time")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
                .padding()
                
                // Recent runs
                if !runs.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Recent Runs")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        List(runs.prefix(5)) { run in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("\(run.distance)m")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                        Text(run.formattedTime)
                                            .font(.headline)
                                    }

                                    Spacer()

                                    Text(formatRunDate(run.date))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }

                                if !run.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "note.text")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                            .padding(.top, 1)

                                        Text(run.notes)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                        .listStyle(PlainListStyle())
                    }
                } else {
                    Spacer()
                    Text("No runs yet")
                        .foregroundColor(.gray)
                    Text("Start running with your Apple Watch!")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                }
                
                Spacer()
            }
            .navigationBarHidden(true)
        }
    }
    
    private var averageTime: String {
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
    
    private func formatRunDate(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            // Today: "today 2:34 PM"
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "today \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            // Yesterday: "yesterday 3:45 PM"
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "yesterday \(formatter.string(from: date))"
        } else {
            // Other days: "9/4 11:10 AM"
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d h:mm a"
            return formatter.string(from: date)
        }
    }
}
