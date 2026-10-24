// App/Sources/Onboarding/OnboardingView.swift
//
// First-launch introduction: what the app does, the place to plan for (current location or
// one picked later), units and clock, and where plans and widgets live. Shown once; screenshot
// runs show it only with `-showOnboarding`.

import PlannerKit
import SwiftUI

enum OnboardingKeys {
    static let completed = "onboarding.completed"

    /// Whether to present the introduction at launch.
    static func shouldShow(arguments: [String] = ProcessInfo.processInfo.arguments, defaults: UserDefaults = .standard) -> Bool {
        if arguments.contains("-showOnboarding") { return true }
        if arguments.contains("-fixedDate") { return false }
        return !defaults.bool(forKey: completed)
    }
}

struct OnboardingView: View {
    enum Page: Int, CaseIterable { case welcome, place, units, plans }

    @Environment(PillSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.unitSystem) private var units: UnitSystem = .metric
    @AppStorage(SettingsKeys.clockStyle) private var clock: ClockStyle = .twentyFourHour
    @State private var page: Page = .welcome
    @State private var locating = false
    @State private var locationMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page != .plans {
                    Button("Skip", action: finish)
                        .accessibilityIdentifier("onboarding.skip")
                }
            }
            .padding(.horizontal)
            .frame(height: 44)
            TabView(selection: $page) {
                welcome.tag(Page.welcome)
                place.tag(Page.place)
                unitsPage.tag(Page.units)
                plans.tag(Page.plans)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            Button {
                if let next = Page(rawValue: page.rawValue + 1) {
                    withAnimation { page = next }
                } else {
                    finish()
                }
            } label: {
                Text(page == .plans ? "Start planning" : "Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .accessibilityIdentifier(page == .plans ? "onboarding.start" : "onboarding.next")
        }
        .background(Color(.systemGroupedBackground))
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: OnboardingKeys.completed)
        dismiss()
    }

    // MARK: Pages

    private var welcome: some View {
        OnboardingPage(systemImage: "sun.horizon.fill", tint: .orange, title: "Plan the light",
                       message: "Know where the Sun, Moon and Milky Way will be, anywhere and at any time, and work out the shot before you leave.") {
            FeatureRow(systemImage: "map", title: "Planner", text: "Sun, Moon and core directions on a map, with the time bar and panels.")
            FeatureRow(systemImage: "square.grid.2x2", title: "Tools", text: "Sun, Moon, Milky Way, meteor showers, eclipses and photography calculators.")
            FeatureRow(systemImage: "camera.viewfinder", title: "Augmented reality", text: "See the paths over the camera view where you stand.")
        }
    }

    private var place: some View {
        OnboardingPage(systemImage: "location.circle.fill", tint: .blue, title: "Your place",
                       message: "Times and directions are worked out for one place. Use where you are now, or choose any place from the place bar later.") {
            VStack(spacing: 12) {
                ValueRow("Now planning for", session.location.name)
                    .accessibilityIdentifier("onboarding.place")
                Button {
                    useCurrentLocation()
                } label: {
                    HStack {
                        Label("Use my location", systemImage: "location.fill")
                        if locating { Spacer(); ProgressView() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(locating)
                if let locationMessage {
                    Text(locationMessage).font(.footnote).foregroundStyle(.subdued)
                }
                Text("Your location stays on this iPhone. Lumora has no account and sends nothing about you anywhere.")
                    .font(.footnote)
                    .foregroundStyle(.subdued)
            }
        }
    }

    private var unitsPage: some View {
        OnboardingPage(systemImage: "ruler.fill", tint: .teal, title: "Units and time",
                       message: "Pick how distances and times are shown. You can change these in Settings.") {
            VStack(spacing: 16) {
                Picker("Units", selection: $units) {
                    Text("Metric").tag(UnitSystem.metric)
                    Text("Imperial").tag(UnitSystem.imperial)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("onboarding.units")
                Picker("Clock", selection: $clock) {
                    Text("24-hour").tag(ClockStyle.twentyFourHour)
                    Text("12-hour").tag(ClockStyle.twelveHour)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("onboarding.clock")
                Text("Times are always shown in the planned place's own time zone.")
                    .font(.footnote)
                    .foregroundStyle(.subdued)
            }
        }
    }

    private var plans: some View {
        OnboardingPage(systemImage: "bookmark.circle.fill", tint: .indigo, title: "Plans and widgets",
                       message: "Save a moment from the Planner as a plan, with a reminder and a calendar event. Add widgets to see the light and your next plan at a glance.") {
            FeatureRow(systemImage: "bookmark", title: "My Stuff", text: "Plans and favourite places, shareable as a file.")
            FeatureRow(systemImage: "rectangle.on.rectangle", title: "Widgets", text: "Sun, Moon, Milky Way and next plan, on the Home and Lock Screen.")
        }
    }

    private func useCurrentLocation() {
        locating = true
        locationMessage = nil
        Task {
            defer { locating = false }
            do {
                session.select(try await PlaceSearch.currentLocation())
            } catch {
                locationMessage = error.localizedDescription
            }
        }
    }
}

private struct OnboardingPage<Content: View>: View {
    let systemImage: String
    let tint: Color
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: systemImage)
                    .font(.system(size: 64))
                    .foregroundStyle(tint)
                    .padding(.top, 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.subdued)
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
        }
    }
}

private struct FeatureRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.subdued)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
