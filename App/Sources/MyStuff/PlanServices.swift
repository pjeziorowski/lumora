// App/Sources/MyStuff/PlanServices.swift
//
// System services for plans: map thumbnails (MKMapSnapshotter), reminders (local
// notifications), calendar events (EventKit, write-only access) and sharing (text, image
// and the JSON exchange file).

import CoreTransferable
import EventKit
@preconcurrency import MapKit
import PlannerKit
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

enum PlanThumbnail {
    /// A square map image around the plan's pin, with the pin and the target drawn on it.
    @MainActor
    static func make(for plan: Plan, size: CGFloat = 160) async -> Data? {
        let options = MKMapSnapshotter.Options()
        let center = CLLocationCoordinate2D(latitude: max(-85, min(85, plan.location.latitude)), longitude: plan.location.longitude)
        options.region = MKCoordinateRegion(center: center, latitudinalMeters: 8000, longitudinalMeters: 8000)
        options.size = CGSize(width: size, height: size)
        options.pointOfInterestFilter = .excludingAll
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let renderer = UIGraphicsImageRenderer(size: options.size)
        let image = renderer.image { _ in
            snapshot.image.draw(at: .zero)
            if let target = plan.target {
                let a = snapshot.point(for: center)
                let b = snapshot.point(for: CLLocationCoordinate2D(latitude: target.point.latitude, longitude: target.point.longitude))
                let line = UIBezierPath()
                line.move(to: a)
                line.addLine(to: b)
                line.lineWidth = 2
                UIColor.black.setStroke()
                line.stroke()
                UIColor.black.setFill()
                UIBezierPath(ovalIn: CGRect(x: b.x - 4, y: b.y - 4, width: 8, height: 8)).fill()
            }
            let p = snapshot.point(for: center)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)).fill()
            UIColor.systemRed.setFill()
            UIBezierPath(ovalIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)).fill()
        }
        return image.pngData()
    }
}

enum PlanReminders {
    /// Schedules (or replaces) the plan's reminder; returns false when not allowed.
    static func schedule(_ plan: Plan) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [plan.id.uuidString])
        guard let fire = plan.reminderDate, fire > Date() else { return true }
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
        let content = UNMutableNotificationContent()
        content.title = plan.name.isEmpty ? String(localized: "Plan") : plan.name
        content.body = String(localized: "Starts in \(plan.reminderMinutes ?? 0) minutes at \(plan.location.name).")
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let request = UNNotificationRequest(identifier: plan.id.uuidString, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        return (try? await center.add(request)) != nil
    }

    static func cancel(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }
}

enum PlanCalendar {
    /// Adds a one-hour event at the plan's time; returns false when access is denied.
    static func add(_ plan: Plan) async -> Bool {
        let store = EKEventStore()
        guard (try? await store.requestWriteOnlyAccessToEvents()) == true else { return false }
        let event = EKEvent(eventStore: store)
        event.title = plan.name.isEmpty ? String(localized: "Photo plan") : plan.name
        event.startDate = plan.instant
        event.endDate = plan.instant.addingTimeInterval(3600)
        event.timeZone = plan.location.timeZone
        event.location = plan.location.name
        event.notes = plan.shareText()
        event.calendar = store.defaultCalendarForNewEvents
        return (try? store.save(event, span: .thisEvent)) != nil
    }
}

/// The JSON exchange file, for ShareLink and the Files app.
struct PlanFile: Transferable {
    let archive: PlanArchive

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { file in
            try file.archive.encoded()
        }
        .suggestedFileName("Lumora plans.json")
    }
}
