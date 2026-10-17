import Foundation

enum NumericInput {
    static func value(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let decimal = locale.decimalSeparator ?? "."
        let grouping = locale.groupingSeparator ?? ","
        let parts = trimmed.components(separatedBy: decimal)
        guard parts.count <= 2 else { return nil }
        var integer = parts[0]
        if !grouping.isEmpty, grouping != decimal, integer.contains(grouping) {
            let groups = integer.components(separatedBy: grouping)
            var first = groups[0]
            if first.hasPrefix("-") || first.hasPrefix("+") { first.removeFirst() }
            // Accept correctly grouped input such as 1,700, but reject 1,70 or 1,,700.
            guard (1...3).contains(first.count), digitsOnly(first),
                  groups.dropFirst().allSatisfy({ $0.count == 3 && digitsOnly($0) }) else { return nil }
            integer = groups.joined()
        }
        if parts.count == 2, !grouping.isEmpty, parts[1].contains(grouping) { return nil }
        let normalized = integer + (parts.count == 2 ? "." + parts[1] : "")
        guard let number = Double(normalized), number.isFinite else { return nil }
        return number
    }

    static func valid(_ text: String, in range: ClosedRange<Double>) -> Bool {
        value(text).map(range.contains) ?? false
    }

    private static func digitsOnly(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { (48...57).contains($0) }
    }
}
