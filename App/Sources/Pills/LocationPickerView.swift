// App/Sources/Pills/LocationPickerView.swift
//
// Shared location picker: current location, place search, typed coordinates, recent
// places and sample places. Picking one updates the shared PillSession and dismisses.

import PlannerKit
import SwiftUI

struct LocationPickerView: View {
    @Environment(PillSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.coordinateStyle) private var coordinateStyle: CoordinateStyle = .decimal

    @State private var query = ""
    @State private var results: [PillLocation] = []
    @State private var searching = false
    @State private var locating = false
    @State private var resolvingCoordinates = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let typed = CoordinateParser.parse(query) {
                    Section("Coordinates") {
                        Button {
                            useCoordinates(typed.latitude, typed.longitude)
                        } label: {
                            HStack {
                                Label(Formatting.coordinate(latitude: typed.latitude, longitude: typed.longitude,
                                                            style: coordinateStyle),
                                      systemImage: "scope")
                                if resolvingCoordinates {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(resolvingCoordinates)
                    }
                }

                if !query.isEmpty {
                    Section("Search results") {
                        if searching && results.isEmpty {
                            ProgressView()
                        } else if results.isEmpty {
                            Text("No places found.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(results) { place in
                            placeRow(place)
                        }
                    }
                }

                Section {
                    Button {
                        useCurrentLocation()
                    } label: {
                        HStack {
                            Label("Current location", systemImage: "location.fill")
                            if locating {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(locating)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if !session.recents.isEmpty {
                    Section("Recent") {
                        ForEach(session.recents) { placeRow($0) }
                    }
                }

                Section("Sample places") {
                    ForEach(PillLocation.samples) { placeRow($0) }
                }
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Place, address or coordinates")
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: query) {
                await runSearch()
            }
        }
    }

    private func placeRow(_ place: PillLocation) -> some View {
        Button {
            choose(place)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .foregroundStyle(.primary)
                let coordinate = Formatting.coordinate(latitude: place.latitude, longitude: place.longitude, style: coordinateStyle)
                Text("\(coordinate) · \(place.timeZoneIdentifier)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func runSearch() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2, CoordinateParser.parse(text) == nil else {
            results = []
            return
        }
        // Debounce typing; a newer query cancels this task.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        let found = (try? await PlaceSearch.search(text)) ?? []
        guard !Task.isCancelled else { return }
        results = found
    }

    private func useCurrentLocation() {
        locating = true
        errorMessage = nil
        Task {
            defer { locating = false }
            do {
                choose(try await PlaceSearch.currentLocation())
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func useCoordinates(_ latitude: Double, _ longitude: Double) {
        resolvingCoordinates = true
        Task {
            let place = await PlaceSearch.resolve(latitude: latitude, longitude: longitude, elevation: 0)
            resolvingCoordinates = false
            choose(place)
        }
    }

    private func choose(_ place: PillLocation) {
        session.select(place)
        dismiss()
    }
}
