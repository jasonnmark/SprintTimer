import Foundation
import SwiftUI

// Manager for handling daily notes separately from run notes
class DailyNotesManager: ObservableObject {
    static let shared = DailyNotesManager()
    
    private let defaults: UserDefaults
    private let appGroupID = "group.com.JasonMark.SprintTimer"
    private let dailyNotesKey = "dailyNotes"
    
    @Published var dailyNotes: [String: String] = [:] // Date string as key
    
    private init() {
        guard let groupDefaults = UserDefaults(suiteName: appGroupID) else {
            self.defaults = UserDefaults.standard
            return
        }
        self.defaults = groupDefaults
        loadNotes()
    }
    
    private func loadNotes() {
        if let savedNotes = defaults.dictionary(forKey: dailyNotesKey) as? [String: String] {
            dailyNotes = savedNotes
        }
    }
    
    private func saveNotes() {
        defaults.set(dailyNotes, forKey: dailyNotesKey)
        defaults.synchronize()
    }
    
    func getNote(for date: Date) -> String {
        let key = dateKey(for: date)
        return dailyNotes[key] ?? ""
    }
    
    func setNote(_ note: String, for date: Date) {
        let key = dateKey(for: date)
        if note.isEmpty {
            dailyNotes.removeValue(forKey: key)
        } else {
            dailyNotes[key] = note
        }
        saveNotes()
        objectWillChange.send()
    }
    
    func hasNote(for date: Date) -> Bool {
        let key = dateKey(for: date)
        return dailyNotes[key] != nil && !dailyNotes[key]!.isEmpty
    }
    
    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Calendar.current.startOfDay(for: date))
    }
    
    // For export - get daily note for a specific run's date
    func getDailyNote(for run: Run) -> String {
        return getNote(for: run.date)
    }
    
    // Clear all daily notes
    func clearAllNotes() {
        dailyNotes.removeAll()
        saveNotes()
        objectWillChange.send()
    }
}
