// App/Sources/Pills/PillHeader.swift
//
// Shared top of the Sun and Moon pills: the chosen place (tap to change) and the date bar.
// Both edit the shared PillSession, so the two pills always show the same place and day.

import PlannerKit
import SwiftUI

struct PillHeader: View {
    @Environment(PillSession.self) private var session
    @AppStorage(SettingsKeys.coordinateStyle) private var coordinateStyle: CoordinateStyle = .decimal
    @State private var showingPicker = false

    var body: some View {
        Section {
            Button {
                showingPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.title3)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.location.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityHint("Choose another place")
            .accessibilityIdentifier("pill.location")
            // Attached to the row, not the Section: List spreads Section modifiers across rows.
            .sheet(isPresented: $showingPicker) {
                LocationPickerView()
            }
            DateBar()
        }
    }

    private var subtitle: String {
        let location = session.location
        let coordinate = Formatting.coordinate(latitude: location.latitude, longitude: location.longitude, style: coordinateStyle)
        return "\(coordinate) · \(Formatting.utcOffset(session.timeZone, at: session.instant))"
    }
}

/// Previous / next day, a date-and-time picker in the place's time zone, and "Now".
struct DateBar: View {
    @Environment(PillSession.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility text sizes the picker gets its own line so the date isn't clipped.
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                picker
                HStack(spacing: 8) {
                    previous
                    next
                    Spacer()
                    now
                }
            }
            .buttonStyle(.borderless)
        } else {
            HStack(spacing: 8) {
                previous
                picker.frame(maxWidth: .infinity)
                next
                now
            }
            .buttonStyle(.borderless)
        }
    }

    private var picker: some View {
        @Bindable var session = session
        return DatePicker("Date and time", selection: $session.instant)
            .labelsHidden()
            .environment(\.timeZone, session.timeZone)
    }

    private var previous: some View {
        Button {
            session.shift(days: -1)
        } label: {
            Image(systemName: "chevron.left")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Previous day")
    }

    private var next: some View {
        Button {
            session.shift(days: 1)
        } label: {
            Image(systemName: "chevron.right")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Next day")
    }

    private var now: some View {
        Button("Now") {
            session.resetToNow()
        }
        .disabled(session.isToday && abs(session.instant.timeIntervalSinceNow) < 60)
    }
}
