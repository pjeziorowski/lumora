// App/Sources/MyStuff/MyStuffView.swift
//
// My Stuff: saved plans (open in the Planner, duplicate, delete, share as text and image,
// export and import as JSON), saved places and the camera list.

import CameraCatalog
import PlannerKit
import SwiftData
import SwiftUI

/// Which tab is showing; plans and places switch to the Planner when opened.
@MainActor
@Observable
final class AppNavigation {
    var tab: AppTab = .planner
}

struct MyStuffView: View {
    enum Section: String, CaseIterable, Identifiable {
        case plans, places, cameras
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .plans: "Plans"
            case .places: "Places"
            case .cameras: "Cameras"
            }
        }
    }

    @State private var section: Section = .plans

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $section) {
                ForEach(Section.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .accessibilityIdentifier("mystuff.section")
            switch section {
            case .plans: PlansList()
            case .places: PlacesList()
            case .cameras: CameraManagerView()
            }
        }
    }
}

private struct PlansList: View {
    @Environment(\.modelContext) private var context
    @Environment(PlannerState.self) private var planner
    @Environment(AppNavigation.self) private var navigation
    @AppStorage(SettingsKeys.clockStyle) private var clock: ClockStyle = .twentyFourHour
    @Query(sort: \PlanRecord.instant) private var records: [PlanRecord]
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        List {
            if records.isEmpty {
                ContentUnavailableView("No plans yet", systemImage: "map",
                                       description: Text("Save one from the Planner with the bookmark button."))
            }
            ForEach(records) { record in
                Button {
                    open(record)
                } label: {
                    PlanRow(record: record, clock: clock)
                }
                .accessibilityIdentifier("plan.row")
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { delete(record) } label: { Label("Delete", systemImage: "trash") }
                    Button { duplicate(record) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                        .tint(.indigo)
                }
                .contextMenu {
                    if let plan = record.plan {
                        ShareLink(item: plan.shareText(clock: clock), subject: Text(plan.name)) {
                            Label("Share as text", systemImage: "text.alignleft")
                        }
                        if let data = record.thumbnail, let image = UIImage(data: data) {
                            ShareLink(item: Image(uiImage: image), preview: SharePreview(plan.name, image: Image(uiImage: image))) {
                                Label("Share map image", systemImage: "photo")
                            }
                        }
                        ShareLink(item: PlanFile(archive: PlanArchive(plans: [plan])),
                                  preview: SharePreview(plan.name)) {
                            Label("Export plan file", systemImage: "square.and.arrow.up")
                        }
                        Button { duplicate(record) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                        Button(role: .destructive) { delete(record) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    importing = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("plans.import")
                ShareLink(item: PlanFile(archive: PlanLibrary.archive(from: context)), preview: SharePreview("Lumora plans")) {
                    Label("Export all", systemImage: "square.and.arrow.up")
                }
                .disabled(records.isEmpty)
                .accessibilityIdentifier("plans.export")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            importFile(result)
        }
        .alert("Import", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func open(_ record: PlanRecord) {
        guard let plan = record.plan else { return }
        navigation.tab = .planner
        Task { await planner.apply(plan) }
    }

    private func duplicate(_ record: PlanRecord) {
        guard let plan = record.plan else { return }
        let copy = PlanRecord(plan.duplicated())
        copy.thumbnail = record.thumbnail
        context.insert(copy)
        try? context.save()
    }

    private func delete(_ record: PlanRecord) {
        PlanReminders.cancel(record.id)
        context.delete(record)
        try? context.save()
    }

    private func importFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let count = try PlanLibrary.importArchive(PlanArchive.decode(Data(contentsOf: url)), into: context)
            message = String(localized: "Imported \(count) items.")
        } catch PlanArchive.ImportError.newerVersion {
            message = String(localized: "This file was made by a newer version of Lumora.")
        } catch {
            message = String(localized: "This file is not a Lumora plan file.")
        }
    }
}

private struct PlanRow: View {
    let record: PlanRecord
    let clock: ClockStyle

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let data = record.thumbnail, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary).overlay { Image(systemName: "map").foregroundStyle(.secondary) }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(record.name.isEmpty ? String(localized: "Untitled plan") : record.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let plan = record.plan {
                    Text(stamp(plan)).font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(plan.location.name)
                        if plan.reminderMinutes != nil { Image(systemName: "bell.fill").accessibilityLabel("Reminder") }
                        if plan.target != nil { Image(systemName: "scope").accessibilityLabel("Target pin") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .task(id: record.id) {
            guard record.thumbnail == nil, let plan = record.plan else { return }
            record.thumbnail = await PlanThumbnail.make(for: plan)
        }
    }

    private func stamp(_ plan: Plan) -> String {
        let zone = plan.location.timeZone
        let day = plan.instant.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: zone))
        return "\(day) · \(Formatting.clockTime(plan.instant, timeZone: zone, style: clock))"
    }
}

private struct PlacesList: View {
    @Environment(\.modelContext) private var context
    @Environment(PlannerState.self) private var planner
    @Environment(AppNavigation.self) private var navigation
    @AppStorage(SettingsKeys.coordinateStyle) private var coordinates: CoordinateStyle = .decimal
    @Query(sort: \PlaceRecord.created) private var records: [PlaceRecord]

    var body: some View {
        List {
            Section {
                Button {
                    context.insert(PlaceRecord(SavedPlace(location: planner.session.location)))
                    try? context.save()
                } label: {
                    Label("Save \(planner.session.location.name)", systemImage: "plus")
                }
                .accessibilityIdentifier("places.add")
            }
            Section {
                ForEach(records) { record in
                    if let place = record.place {
                        Button {
                            navigation.tab = .planner
                            planner.select(place.location)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(place.location.name).font(.headline).foregroundStyle(.primary)
                                Text(Formatting.coordinate(latitude: place.location.latitude, longitude: place.location.longitude,
                                                           style: coordinates))
                                    .font(.subheadline).foregroundStyle(.secondary)
                                if !place.notes.isEmpty { Text(place.notes).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                context.delete(record)
                                try? context.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Saved places")
            }
        }
    }
}
