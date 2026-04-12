import SwiftUI
import SwiftData

@main
struct SprintTimerApp: App {
    @State private var isReady = false

    private let dataManager = DataManager.shared
    private let syncManager = SyncManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady {
                    iOSContentView()
                } else {
                    LaunchLoadingView()
                        .onAppear {
                            // Give the run loop a tick so the loading view renders
                            // before SwiftData queries start pulling data
                            DispatchQueue.main.async {
                                isReady = true
                            }
                        }
                }
            }
            .preferredColorScheme(.dark)
        }
        .modelContainer(dataManager.modelContainer)
    }
}

struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "figure.run")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                Text("Sprint Timer")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                ProgressView()
                    .tint(.green)
            }
        }
    }
}
