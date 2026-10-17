import Foundation

enum RestingEquation: String, CaseIterable, Identifiable {
    case male, female, manual
    var id: String { rawValue }
    var title: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .manual: "Custom resting calories"
        }
    }
}

struct CalorieInput {
    var weightKG: Double
    var heightCM: Double
    var ageYears: Int
    var equation: RestingEquation
    var manualRestingKcal: Double
    var plannedActiveKcal: Double
    var surplusKcal: Double
    var targetWeightKG: Double
    var proteinGramsPerKG: Double
    var proteinGoalGrams: Double? = nil
}

struct EnergyReading: Sendable {
    var activeKcal: Double?
    var basalKcal: Double?

    /// Missing is distinct from zero. Even a nonnil sum can be incomplete.
    var recordedTotal: Double? {
        guard let activeKcal, let basalKcal else { return nil }
        return activeKcal + basalKcal
    }
}

struct CaloriePlan {
    var restingKcal: Double
    var activeKcal: Double
    var surplusKcal: Double
    var proteinGrams: Double
    var fatGrams: Double
    var carbGrams: Double
    var projectedBurn: Double { restingKcal + activeKcal }
    var targetKcal: Double { projectedBurn + surplusKcal }
}

enum CalorieEngine {
    static func restingCalories(for input: CalorieInput) -> Double {
        let baseline: Double
        if input.equation == .manual {
            baseline = input.manualRestingKcal
        } else {
            let offset = input.equation == .male ? 5.0 : -161.0
            baseline = 10 * input.weightKG + 6.25 * input.heightCM
                - 5 * Double(input.ageYears) + offset
        }
        return max(500, baseline)
    }

    static func plan(input: CalorieInput, energy: EnergyReading, elapsedFraction: Double) -> CaloriePlan {
        let safeBaseline = restingCalories(for: input)
        let remainingFraction = 1 - min(1, max(0, elapsedFraction))
        // Keep the baseline floor if the Watch was off or samples arrive late.
        let resting = max(safeBaseline, (energy.basalKcal ?? 0) + safeBaseline * remainingFraction)
        // The activity allowance is REPLACED by higher recorded activity, never added to it.
        let active = max(0, input.plannedActiveKcal, energy.activeKcal ?? 0)
        let surplus = input.weightKG < input.targetWeightKG ? max(0, input.surplusKcal) : 0
        let target = resting + active + surplus
        let protein = input.proteinGoalGrams ?? (input.weightKG * input.proteinGramsPerKG)
        let fat = min(input.weightKG * 0.8, max(0, (target - 4 * protein) / 9))
        let carbs = max(0, (target - 4 * protein - 9 * fat) / 4)
        return CaloriePlan(restingKcal: resting, activeKcal: active, surplusKcal: surplus,
                           proteinGrams: protein, fatGrams: fat, carbGrams: carbs)
    }
}
