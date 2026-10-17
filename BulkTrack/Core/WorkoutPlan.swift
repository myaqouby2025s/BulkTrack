import Foundation

struct PlannedExercise: Identifiable {
    let id: String
    let name: String
    let sets: Int
    let reps: String
    var isTimed: Bool { reps.localizedCaseInsensitiveContains("seconds") }
}
