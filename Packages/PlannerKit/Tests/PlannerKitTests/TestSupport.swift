// Packages/PlannerKit/Tests/PlannerKitTests/TestSupport.swift
//
// Accuracy-report helpers, same shape as AstroCoreTests/GoldenData.swift so
// scripts/test-packages.sh picks up the "ACCURACY |" lines.

import Foundation

/// Accumulates absolute errors for an accuracy report.
struct ErrorStats: CustomStringConvertible {
    let name: String
    let unit: String
    private(set) var values: [Double] = []
    private(set) var worst = ""

    init(_ name: String, unit: String) {
        self.name = name
        self.unit = unit
    }

    mutating func add(_ error: Double, _ label: @autoclosure () -> String) {
        if error > (values.max() ?? -1) { worst = label() }
        values.append(error)
    }

    var count: Int { values.count }
    var max: Double { values.max() ?? 0 }
    var mean: Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }

    var description: String {
        String(format: "%@: n=%d  mean=%.3f %@  max=%.3f %@  (worst: %@)", name, count, mean, unit, max, unit, worst)
    }
}

enum Report {
    static func line(_ s: CustomStringConvertible) {
        print("ACCURACY | \(s)")
    }
}
