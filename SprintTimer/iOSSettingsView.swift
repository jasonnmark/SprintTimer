import SwiftUI

struct iOSSettingsView: View {
    @AppStorage("useGPS", store: UserDefaults(suiteName: "group.com.yourname.sprinttimer")) private var useGPS = true
    @AppStorage("useHealthKit", store: UserDefaults(suiteName: "group.com.yourname.sprinttimer")) private var useHealthKit = true
    @AppStorage("trackWeather", store: UserDefaults(suiteName: "group.com.yourname.sprinttimer")) private var trackWeather = true
    @AppStorage("trackAltitude", store: UserDefaults(suiteName: "group.com.yourname.sprinttimer")) private var trackAltitude = true
    @AppStorage("useMotionStart", store: UserDefaults(suiteName: "group.com.yourname.sprinttimer")) private var useMotionStart = false
    @AppStorage("useCountdown", store: UserDefaults(suiteName: "group.com.yourname.sprinttimer")) private var useCountdown = false
    @AppStorage("countdownTime", store: UserDefaults(suiteName: "group.com.yourname.sprinttimer")) private var countdownTime = 10
    @AppStorage("saveTapTime", store: UserDefaults(suiteName: "group.com.yourname.sprinttimer")) private var saveTapTime = true
    @AppStorage("saveGPSTime", store: UserDefaults(suiteName: "group.com.yourname.sprinttimer")) private var saveGPSTime = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Start Options")) {
                    VStack(alignment: .leading) {
                        Text("Start Method")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Picker("", selection: startMethod) {
                            Text("Tap to Start").tag(0)
                            Text("Motion Start").tag(1)
                            Text("Countdown").tag(2)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .labelsHidden()
                    }
                    
                    if startMethod.wrappedValue == 2 {
                        Picker("Countdown Time", selection: $countdownTime) {
                            Text("10 seconds").tag(10)
                            Text("15 seconds").tag(15)
                            Text("20 seconds").tag(20)
                            Text("30 seconds").tag(30)
                        }
                    }
                    
                    Text(startMethodDescription)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Section(header: Text("Data Collection")) {
                    Toggle("GPS Verification", isOn: $useGPS)
                    Toggle("HealthKit Integration", isOn: $useHealthKit)
                    Toggle("Weather Data", isOn: $trackWeather)
                    Toggle("Altitude Tracking", isOn: $trackAltitude)
                }
                
                Section(header: Text("Save Options")) {
                    Toggle("Save Tap Time", isOn: $saveTapTime)
                    Toggle("Save GPS Time", isOn: $saveGPSTime)
                    
                    if saveTapTime && saveGPSTime {
                        Text("Both tap and GPS times will be recorded")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Section(header: Text("Data Collected")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Time & Date", systemImage: "clock")
                        Label("Distance & Time", systemImage: "timer")
                        
                        if useHealthKit {
                            Label("Heart Rate (start/end)", systemImage: "heart")
                            Label("Steps & Stride Length", systemImage: "figure.walk")
                        }
                        
                        if useGPS {
                            Label("Location & Speed", systemImage: "location")
                            Label("Actual Distance", systemImage: "map")
                        }
                        
                        if trackAltitude {
                            Label("Altitude", systemImage: "arrow.up.and.down")
                        }
                        
                        if trackWeather {
                            Label("Temperature", systemImage: "thermometer")
                            Label("Humidity & Pressure", systemImage: "cloud")
                            Label("Air Quality", systemImage: "aqi.medium")
                        }
                    }
                    .font(.system(size: 14))
                }
                
                Section {
                    Text("Note: These settings sync with your Apple Watch automatically")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Settings")
        }
    }
    
    private var startMethod: Binding<Int> {
        Binding(
            get: {
                if useCountdown { return 2 }
                else if useMotionStart { return 1 }
                else { return 0 }
            },
            set: { value in
                useMotionStart = (value == 1)
                useCountdown = (value == 2)
            }
        )
    }
    
    private var startMethodDescription: String {
        switch startMethod.wrappedValue {
        case 0:
            return "Timer starts immediately when you tap Start"
        case 1:
            return "Timer starts when motion is detected"
        case 2:
            return "Timer starts after countdown with audio cues"
        default:
            return ""
        }
    }
}
