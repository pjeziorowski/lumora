// Packages/CameraCatalog/Sources/CameraCatalog/CameraCatalog.swift
//
// Camera bodies: the bundled catalogue (Resources/cameras.json, built by
// Tools/cameras/build_catalog.py from manufacturers' specifications) plus the user's custom
// cameras, favourites and default camera, persisted as JSON in UserDefaults. Pixel pitch,
// crop factor and the default circle of confusion are derived from the sensor (OpticsCore).

import Foundation
import Observation
import OpticsCore

public struct Camera: Sendable, Hashable, Codable, Identifiable {
    public enum Category: String, Sendable, Hashable, Codable, CaseIterable {
        case mirrorless, dslr, compact, rangefinder, drone, phone, custom
    }

    public var id: String
    public var brand: String
    public var model: String
    public var category: Category
    public var sensorWidth: Double
    public var sensorHeight: Double
    public var pixelsWide: Int
    public var pixelsHigh: Int
    /// Phone sensor sizes are nominal optical formats, not measured sizes.
    public var approximate: Bool
    /// Overrides the default circle of confusion (mm) when set.
    public var cocOverride: Double?

    public init(id: String = UUID().uuidString, brand: String, model: String, category: Category = .custom,
                sensorWidth: Double, sensorHeight: Double, pixelsWide: Int, pixelsHigh: Int,
                approximate: Bool = false, cocOverride: Double? = nil) {
        self.id = id
        self.brand = brand
        self.model = model
        self.category = category
        self.sensorWidth = sensorWidth
        self.sensorHeight = sensorHeight
        self.pixelsWide = pixelsWide
        self.pixelsHigh = pixelsHigh
        self.approximate = approximate
        self.cocOverride = cocOverride
    }

    public var name: String { "\(brand) \(model)" }
    public var sensor: Sensor {
        Sensor(widthMM: sensorWidth, heightMM: sensorHeight, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh)
    }
    public var coc: Double { cocOverride ?? sensor.defaultCoC }
    public var pixelPitchMicrons: Double { sensor.pixelPitchMicrons ?? 0 }
    public var cropFactor: Double { sensor.cropFactor }

    /// "Full frame", "APS-C", "Micro Four Thirds" …, from the crop factor.
    public var formatName: String {
        switch cropFactor {
        case ..<0.9: "Medium format"
        case ..<1.15: "Full frame"
        case ..<1.45: "APS-H"
        case ..<1.75: "APS-C"
        case ..<2.2: "Micro Four Thirds"
        case ..<3.2: "1-inch"
        default: "Small sensor"
        }
    }

    /// Checks a custom entry: positive sizes up to 60 × 60 mm, at least 100 px a side.
    public var isValid: Bool {
        sensorWidth > 0 && sensorHeight > 0 && sensorWidth <= 60 && sensorHeight <= 60
            && pixelsWide >= 100 && pixelsHigh >= 100 && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

public enum CameraCatalog {
    /// Diagonal of a 36 × 24 mm full-frame sensor in mm, the reference for crop factors.
    public static let fullFrameDiagonalMM = (36.0 * 36.0 + 24.0 * 24.0).squareRoot()

    struct File: Decodable {
        let version: Int
        let cameras: [Camera]
    }

    /// The bundled catalogue, sorted by brand then model as listed.
    public static let bundled: [Camera] = {
        guard let url = Bundle.module.url(forResource: "cameras", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.cameras
    }()

    public static var brands: [String] {
        var seen = Set<String>()
        return bundled.map(\.brand).filter { seen.insert($0).inserted }
    }

    /// Case- and diacritic-insensitive search over brand and model ("a7 iv" finds "α7 IV").
    public static func search(_ text: String, in cameras: [Camera] = bundled) -> [Camera] {
        let words = normalize(text).split(separator: " ")
        guard !words.isEmpty else { return cameras }
        return cameras.filter { camera in
            let haystack = normalize(camera.name)
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "α", with: "a")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "-", with: " ")
    }

    public static func camera(id: String) -> Camera? { bundled.first { $0.id == id } }

    /// Used when nothing is chosen: a generic 24 MP full-frame body.
    public static let fallback = Camera(id: "generic-full-frame", brand: "Generic", model: "Full frame 24 MP",
                                        category: .custom, sensorWidth: 36, sensorHeight: 24,
                                        pixelsWide: 6000, pixelsHigh: 4000)
}

/// The user's cameras: custom bodies, favourites and the default camera.
@MainActor
@Observable
public final class CameraStore {
    public private(set) var custom: [Camera]
    public private(set) var favourites: Set<String>
    public private(set) var defaultID: String

    @ObservationIgnored private let defaults: UserDefaults?
    static let customKey = "cameras.custom"
    static let favouritesKey = "cameras.favourites"
    static let defaultKey = "cameras.default"

    public init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        custom = defaults?.data(forKey: Self.customKey).flatMap { try? JSONDecoder().decode([Camera].self, from: $0) } ?? []
        favourites = Set(defaults?.stringArray(forKey: Self.favouritesKey) ?? [])
        defaultID = defaults?.string(forKey: Self.defaultKey) ?? CameraCatalog.fallback.id
    }

    public var all: [Camera] { custom + CameraCatalog.bundled }

    public func camera(id: String) -> Camera? {
        id == CameraCatalog.fallback.id ? CameraCatalog.fallback : all.first { $0.id == id }
    }

    public var defaultCamera: Camera { camera(id: defaultID) ?? CameraCatalog.fallback }

    public func setDefault(_ camera: Camera) {
        defaultID = camera.id
        defaults?.set(defaultID, forKey: Self.defaultKey)
    }

    public func toggleFavourite(_ camera: Camera) {
        if favourites.contains(camera.id) { favourites.remove(camera.id) } else { favourites.insert(camera.id) }
        defaults?.set(Array(favourites).sorted(), forKey: Self.favouritesKey)
    }

    /// Adds or replaces a custom camera. Returns false for an invalid entry.
    @discardableResult
    public func save(_ camera: Camera) -> Bool {
        guard camera.isValid else { return false }
        var entry = camera
        entry.category = .custom
        if let index = custom.firstIndex(where: { $0.id == entry.id }) {
            custom[index] = entry
        } else {
            custom.insert(entry, at: 0)
        }
        persist()
        return true
    }

    public func delete(_ camera: Camera) {
        custom.removeAll { $0.id == camera.id }
        favourites.remove(camera.id)
        if defaultID == camera.id { defaultID = CameraCatalog.fallback.id }
        persist()
        defaults?.set(Array(favourites).sorted(), forKey: Self.favouritesKey)
        defaults?.set(defaultID, forKey: Self.defaultKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(custom) { defaults?.set(data, forKey: Self.customKey) }
    }
}
