import SwiftUI
import SwiftData

struct iOSHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomRunType.orderIndex) private var customRunTypes: [CustomRunType]
    @State private var showingAddRun = false
    @State private var editMode: EditMode = .inactive
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Default Runs")) {
                    ForEach(defaultRuns, id: \.distance) { run in
                        HStack {
                            Text(run.displayName)
                                .font(.headline)
                            Spacer()
                            Image(systemName: "lock.fill")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section(header: Text("Custom Runs")) {
                    if customRunTypes.isEmpty && editMode == .inactive {
                        Text("No custom runs yet")
                            .foregroundColor(.gray)
                            .italic()
                    } else {
                        ForEach(customRunTypes) { runType in
                            HStack {
                                Text(runType.displayName)
                                    .font(.headline)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: deleteCustomRuns)
                        .onMove(perform: moveCustomRuns)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Sprint Timer")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddRun = true
                    }) {
                        Image(systemName: "plus")
                    }
                    .disabled(editMode == .active)
                }
            }
            .environment(\.editMode, $editMode)
            .sheet(isPresented: $showingAddRun) {
                AddCustomRunView()
            }
        }
        .onAppear {
            ensureDefaultRunTypes()
        }
    }
    
    private var defaultRuns: [(displayName: String, distance: Int)] {
        [
            (displayName: "100m", distance: 100),
            (displayName: "200m", distance: 200),
            (displayName: "400m", distance: 400)
        ]
    }
    
    private func ensureDefaultRunTypes() {
        // Check if we need to create default run types
        let descriptor = FetchDescriptor<CustomRunType>(
            predicate: #Predicate { $0.isDefault == true }
        )
        
        do {
            let existingDefaults = try modelContext.fetch(descriptor)
            if existingDefaults.isEmpty {
                // Create default run types
                for (index, run) in defaultRuns.enumerated() {
                    let runType = CustomRunType(
                        name: "",
                        distance: run.distance,
                        isDefault: true,
                        orderIndex: index
                    )
                    modelContext.insert(runType)
                }
                try modelContext.save()
            }
        } catch {
            print("Error checking/creating defaults: \(error)")
        }
    }
    
    private func deleteCustomRuns(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(customRunTypes[index])
        }
    }
    
    private func moveCustomRuns(from source: IndexSet, to destination: Int) {
        var reorderedTypes = customRunTypes
        reorderedTypes.move(fromOffsets: source, toOffset: destination)
        
        for (index, runType) in reorderedTypes.enumerated() {
            runType.orderIndex = index + 100 // Start custom runs at index 100
        }
    }
}

struct AddCustomRunView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var distance = ""
    @State private var selectedPreset = 0
    
    let presetDistances = [
        ("Custom", 0),
        ("50m", 50),
        ("60m", 60),
        ("110m Hurdles", 110),
        ("300m", 300),
        ("400m Hurdles", 400),
        ("800m", 800),
        ("1500m", 1500),
        ("Mile", 1609),
        ("5K", 5000),
        ("10K", 10000)
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Run Details")) {
                    TextField("Run Name (e.g., Backwards, Hurdles)", text: $name)
                    
                    Picker("Distance Preset", selection: $selectedPreset) {
                        ForEach(0..<presetDistances.count, id: \.self) { index in
                            Text(presetDistances[index].0).tag(index)
                        }
                    }
                    .onChange(of: selectedPreset) { newValue in
                        if newValue > 0 {
                            distance = String(presetDistances[newValue].1)
                        }
                    }
                    
                    HStack {
                        TextField("Distance in meters", text: $distance)
                            .keyboardType(.numberPad)
                        Text("meters")
                            .foregroundColor(.gray)
                    }
                }
                
                Section {
                    Text("Examples:")
                        .font(.headline)
                    Text("• 400m Hurdles")
                    Text("• Backwards 100m")
                    Text("• Hill Sprint 200m")
                    Text("• Beach Run 150m")
                }
                .font(.caption)
                .foregroundColor(.gray)
            }
            .navigationTitle("Add Custom Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveCustomRun()
                    }
                    .disabled(name.isEmpty || distance.isEmpty)
                }
            }
        }
    }
    
    private func saveCustomRun() {
        guard let distanceInt = Int(distance), distanceInt > 0 else { return }
        
        let customRun = CustomRunType(
            name: name,
            distance: distanceInt,
            isDefault: false
        )
        
        modelContext.insert(customRun)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving custom run: \(error)")
        }
    }
}
