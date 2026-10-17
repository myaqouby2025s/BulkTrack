import Foundation

/// Display/entry uses US customary units. Storage and HealthKit keep canonical metric values.
enum USUnits {
    static let poundsPerKilogram = 2.2046226218487757
    static let millilitersPerFluidOunce = 29.5735295625
    static func pounds(_ kilograms: Double) -> Double { kilograms * poundsPerKilogram }
    static func kilograms(_ pounds: Double) -> Double { pounds / poundsPerKilogram }
    static func fluidOunces(_ milliliters: Double) -> Double { milliliters / millilitersPerFluidOunce }
    static func milliliters(_ fluidOunces: Double) -> Double { fluidOunces * millilitersPerFluidOunce }
    static func centimeters(feet: Int, inches: Double) -> Double { (Double(feet * 12) + inches) * 2.54 }
    static func heightParts(_ centimeters: Double) -> (feet: Int, inches: Int) {
        let total = Int((centimeters / 2.54).rounded())
        return (total / 12, total % 12)
    }
    static func number(_ value: Double, digits: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }
    static func weight(_ kilograms: Double) -> String { "\(number(pounds(kilograms), digits: 1)) lb" }
    static func height(_ centimeters: Double) -> String {
        let parts = heightParts(centimeters)
        return "\(parts.feet)′ \(parts.inches)″"
    }
}

