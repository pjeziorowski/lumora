// App/Sources/Planner/PlannerMapView.swift
//
// MKMapView wrapper for the Planner: the draggable observer pin (long-press anywhere to
// drop it), Sun and Moon direction lines and daily paths, and body markers. Geometry comes
// from PlannerKit's `PlannerOverlays`; this file only converts it to MapKit objects.
// Lines are built from MKMapPoints with x unwrapped around the pin so they stay continuous
// across the antimeridian (MapKit draws overlays whose x runs past the world width).

import GeoCore
import MapKit
import PlannerKit
import SwiftUI

struct PlannerMapView: UIViewRepresentable {
    let pin: PillLocation
    let snapshot: PlannerSnapshot?
    let style: PlannerMapStyle
    let recenterToken: Int
    /// Called with the new coordinate when the pin is dropped or dragged.
    let onPinMoved: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = true
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll
        map.accessibilityIdentifier = "planner.map"
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.pinReuseID)
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPressed(_:)))
        press.minimumPressDuration = 0.45
        map.addGestureRecognizer(press)
        context.coordinator.map = map
        map.addAnnotation(context.coordinator.pinAnnotation)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onPinMoved = onPinMoved
        coordinator.apply(style: style, to: map)

        let coordinate = CLLocationCoordinate2D(latitude: max(-85, min(85, pin.latitude)), longitude: pin.longitude)
        if !coordinator.isDragging {
            coordinator.pinAnnotation.coordinate = coordinate
            coordinator.pinAnnotation.title = pin.name
        }
        if coordinator.recenterToken != recenterToken {
            let first = coordinator.recenterToken == nil
            coordinator.recenterToken = recenterToken
            let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 6000, longitudinalMeters: 6000)
            map.setRegion(region, animated: !first)
        }
        coordinator.snapshot = snapshot
        coordinator.rebuildOverlays()
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MKMapViewDelegate {
        static let pinReuseID = "pin"
        static let bodyReuseID = "body"

        weak var map: MKMapView?
        let pinAnnotation = MKPointAnnotation()
        var onPinMoved: ((CLLocationCoordinate2D) -> Void)?
        var snapshot: PlannerSnapshot?
        var recenterToken: Int?
        var isDragging = false
        private var style: PlannerMapStyle?
        private var radius = 2000.0
        private var lastBuilt: (PlannerSnapshot, Double)?
        private var lines: [MKOverlay] = []
        private var markers: [OverlayBody: BodyAnnotation] = [:]

        func apply(style newStyle: PlannerMapStyle, to map: MKMapView) {
            guard newStyle != style else { return }
            style = newStyle
            switch newStyle {
            case .standard: map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
            case .satellite: map.preferredConfiguration = MKImageryMapConfiguration()
            case .hybrid: map.preferredConfiguration = MKHybridMapConfiguration()
            case .terrain: map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .muted)
            }
        }

        // MARK: Overlays

        func rebuildOverlays() {
            guard let map, let snapshot else { return }
            if let last = lastBuilt, last.0 == snapshot, last.1 == radius { return }
            lastBuilt = (snapshot, radius)
            let overlays = PlannerOverlays.build(snapshot, radius: radius)
            let pinPoint = MKMapPoint(CLLocationCoordinate2D(latitude: max(-85, min(85, snapshot.location.latitude)),
                                                             longitude: snapshot.location.longitude))
            let newLines = overlays.lines.map { line -> MKOverlay in
                let points = line.points.map { Self.mapPoint($0, near: pinPoint) }
                let polyline = PlannerPolyline(points: points, count: points.count)
                polyline.style = line
                return polyline
            }
            map.removeOverlays(lines)
            map.addOverlays(newLines, level: .aboveRoads)
            lines = newLines

            for marker in overlays.markers {
                let safe = PlannerOverlays.mercatorSafe(marker.point.normalized)
                let coordinate = CLLocationCoordinate2D(latitude: safe.latitude, longitude: safe.longitude)
                if let existing = markers[marker.body] {
                    existing.coordinate = coordinate
                    if existing.isUp != marker.isAboveHorizon {
                        existing.isUp = marker.isAboveHorizon
                        (map.view(for: existing) as? BodyAnnotationView)?.refresh()
                    }
                } else {
                    let annotation = BodyAnnotation(body: marker.body, isUp: marker.isAboveHorizon)
                    annotation.coordinate = coordinate
                    markers[marker.body] = annotation
                    map.addAnnotation(annotation)
                }
            }
        }

        /// Map point with x shifted by whole world widths to sit nearest the pin's x.
        static func mapPoint(_ p: GeoPoint, near pin: MKMapPoint) -> MKMapPoint {
            let safe = PlannerOverlays.mercatorSafe(p.normalized)
            var point = MKMapPoint(CLLocationCoordinate2D(latitude: safe.latitude, longitude: safe.longitude))
            let world = MKMapSize.world.width
            while point.x - pin.x > world / 2 { point.x -= world }
            while point.x - pin.x < -world / 2 { point.x += world }
            return point
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let rect = mapView.visibleMapRect
            let metersPerPoint = MKMetersPerMapPointAtLatitude(mapView.region.center.latitude)
            let span = min(rect.size.width, rect.size.height) * metersPerPoint
            let newRadius = PlannerOverlays.radius(forVisibleSpan: span)
            // Rebuild only when the zoom changed noticeably.
            if abs(newRadius - radius) / radius > 0.08 {
                radius = newRadius
                rebuildOverlays()
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? PlannerPolyline, let line = polyline.style else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = PlannerColors.uiColor(for: line.body, role: line.role)
            renderer.lineCap = .round
            switch line.role {
            case .now:
                renderer.lineWidth = line.isAboveHorizon ? 4 : 2
                if !line.isAboveHorizon { renderer.lineDashPattern = [6, 5] }
            case .rise, .set:
                renderer.lineWidth = 3
            case .pathUp:
                renderer.lineWidth = 4
            case .pathDown:
                renderer.lineWidth = 1.5
                renderer.lineDashPattern = [2, 5]
            }
            return renderer
        }

        // MARK: Annotations

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let body = annotation as? BodyAnnotation {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: Self.bodyReuseID) as? BodyAnnotationView)
                    ?? BodyAnnotationView(annotation: body, reuseIdentifier: Self.bodyReuseID)
                view.annotation = body
                view.refresh()
                return view
            }
            guard annotation === pinAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.pinReuseID, for: annotation)
            if let marker = view as? MKMarkerAnnotationView {
                marker.markerTintColor = .systemRed
                marker.glyphImage = UIImage(systemName: "camera.fill")
                marker.isDraggable = true
                marker.canShowCallout = false
                marker.displayPriority = .required
                marker.accessibilityLabel = String(localized: "Observer pin")
            }
            return view
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            switch newState {
            case .starting, .dragging:
                isDragging = true
            case .ending, .canceling:
                isDragging = false
                view.dragState = .none
                onPinMoved?(pinAnnotation.coordinate)
            default:
                break
            }
        }

        @objc func longPressed(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map else { return }
            let coordinate = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            pinAnnotation.coordinate = coordinate
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onPinMoved?(coordinate)
        }
    }
}

/// A polyline that remembers which Planner line it draws.
final class PlannerPolyline: MKPolyline {
    var style: OverlayLine?
}

final class BodyAnnotation: MKPointAnnotation {
    let body: OverlayBody
    var isUp: Bool

    init(body: OverlayBody, isUp: Bool) {
        self.body = body
        self.isUp = isUp
        super.init()
    }
}

final class BodyAnnotationView: MKAnnotationView {
    func refresh() {
        guard let body = annotation as? BodyAnnotation else { return }
        let symbol: String
        switch body.body {
        case .sun: symbol = "sun.max.fill"
        case .moon: symbol = "moon.fill"
        case .galacticCenter: symbol = "sparkles"
        }
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        image = UIImage(systemName: symbol, withConfiguration: config)?
            .withTintColor(PlannerColors.uiColor(for: body.body, role: .now), renderingMode: .alwaysOriginal)
        alpha = body.isUp ? 1 : 0.45
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.5
        layer.shadowRadius = 2
        layer.shadowOffset = .zero
        displayPriority = .required
        isAccessibilityElement = true
        accessibilityLabel = body.body == .sun ? String(localized: "Sun") : String(localized: "Moon")
    }
}

/// Line colours: Sun in warm yellows, Moon in cool blues, rise lighter than set.
enum PlannerColors {
    static func uiColor(for body: OverlayBody, role: OverlayRole) -> UIColor {
        switch (body, role) {
        case (.sun, .rise): UIColor(red: 1.00, green: 0.80, blue: 0.20, alpha: 1)
        case (.sun, .set): UIColor(red: 0.95, green: 0.45, blue: 0.10, alpha: 1)
        case (.sun, .pathDown): UIColor(red: 0.95, green: 0.70, blue: 0.20, alpha: 0.8)
        case (.sun, _): UIColor(red: 1.00, green: 0.66, blue: 0.00, alpha: 1)
        case (.moon, .rise): UIColor(red: 0.55, green: 0.80, blue: 1.00, alpha: 1)
        case (.moon, .set): UIColor(red: 0.25, green: 0.45, blue: 0.95, alpha: 1)
        case (.moon, .pathDown): UIColor(red: 0.45, green: 0.65, blue: 1.00, alpha: 0.8)
        case (.moon, _): UIColor(red: 0.40, green: 0.62, blue: 1.00, alpha: 1)
        case (.galacticCenter, _): UIColor(red: 0.78, green: 0.55, blue: 1.00, alpha: 1)
        }
    }

    static func color(for body: OverlayBody, role: OverlayRole) -> Color {
        Color(uiColor: uiColor(for: body, role: role))
    }
}
