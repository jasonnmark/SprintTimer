import SwiftUI
import SwiftData

struct iOSContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            SimpleHomeView()
                .tabItem {
                    Label("Home", systemImage: "figure.run")
                }
                .tag(0)
            
            iOSHistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(1)
            
            iOSSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
            
            iOSExportView()
                .tabItem {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .tag(3)
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
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(run.distance)m")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Text(run.formattedTime)
                                        .font(.headline)
                                }
                                
                                Spacer()
                                
                                Text(run.date, style: .relative)
                                    .font(.caption)
                                    .foregroundColor(.gray)
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
            .onAppear {
                print("DEBUG: iPhone app runs count: \(runs.count)")
                if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.JasonMark.SprintTimer") {
                    let dbURL = groupURL.appendingPathComponent("SprintTimer.sqlite")
                    print("DEBUG: Database exists: \(FileManager.default.fileExists(atPath: dbURL.path))")
                }
            }
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
}
