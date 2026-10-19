// Packages/PlannerKit/Sources/PlannerKit/Widgets/WidgetStore.swift
//
// The few values the app hands to its widgets: the selected place, the clock style and the
// upcoming saved plans, kept in the app group's shared defaults. Without the app-group
// entitlement (unsigned simulator builds) the suite is private to each process and the
// widgets fall back to their placeholders.

import Foundation

public enum WidgetStore {
    public static let appGroup = "group.com.pjeziorowski.lumora"
    static let locationKey = "widget.location"
    static let clockKey = "widget.clock"
    static let plansKey = "widget.plans"

    public static var shared: UserDefaults? { UserDefaults(suiteName: appGroup) }

    public static func save(location: PillLocation, clock: ClockStyle, to defaults: UserDefaults?) {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(location) { defaults.set(data, forKey: locationKey) }
        defaults.set(clock.rawValue, forKey: clockKey)
    }

    public static func location(in defaults: UserDefaults?) -> PillLocation? {
        defaults?.data(forKey: locationKey).flatMap { try? JSONDecoder().decode(PillLocation.self, from: $0) }
    }

    public static func clock(in defaults: UserDefaults?) -> ClockStyle {
        defaults?.string(forKey: clockKey).flatMap(ClockStyle.init(rawValue:)) ?? .twentyFourHour
    }

    /// Keeps the plans still to come, soonest first, at most `limit`.
    public static func save(plans: [WidgetPlan], now: Date, limit: Int = 10, to defaults: UserDefaults?) {
        guard let defaults else { return }
        let upcoming = plans.filter { $0.instant > now }.sorted { $0.instant < $1.instant }.prefix(limit)
        if let data = try? JSONEncoder().encode(Array(upcoming)) { defaults.set(data, forKey: plansKey) }
    }

    public static func plans(in defaults: UserDefaults?) -> [WidgetPlan] {
        defaults?.data(forKey: plansKey).flatMap { try? JSONDecoder().decode([WidgetPlan].self, from: $0) } ?? []
    }
}
