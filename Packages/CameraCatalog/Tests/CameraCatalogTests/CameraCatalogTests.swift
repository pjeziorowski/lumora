// Packages/CameraCatalog/Tests/CameraCatalogTests/CameraCatalogTests.swift
//
// Catalogue integrity and spot checks against manufacturers' published specifications:
// Nikon D750 35.9 × 24.0 mm, 6016 × 4016 px (5.97 µm, as Light Stalking computes);
// Sony α7R IV 35.7 × 23.8 mm, 9504 × 6336 px (3.76 µm); Fujifilm X-T5 23.5 × 15.6 mm,
// 7728 × 5152 px (3.04 µm); Olympus/OM 17.4 × 13.0 mm Four Thirds (crop ≈ 2.0).

import Foundation
import Testing
@testable import CameraCatalog

struct CameraCatalogTests {
    // Golden: 36 × 24 mm diagonal = 43.267 mm (√(36² + 24²)).
    @Test func fullFrameDiagonal() {
        #expect(abs(CameraCatalog.fullFrameDiagonalMM - 43.2666) < 1e-3)
    }

    @Test func catalogueLoadsAndIsSane() {
        let all = CameraCatalog.bundled
        #expect(all.count >= 150)
        #expect(Set(all.map(\.id)).count == all.count)
        for camera in all {
            #expect(camera.isValid, "\(camera.name)")
            // Pixels should be roughly square: aspect of the sensor matches the image within 3%.
            let sensorAspect = camera.sensorWidth / camera.sensorHeight
            let pixelAspect = Double(camera.pixelsWide) / Double(camera.pixelsHigh)
            #expect(abs(sensorAspect / pixelAspect - 1) < 0.03, "\(camera.name)")
            #expect(camera.pixelPitchMicrons > 0.5 && camera.pixelPitchMicrons < 10, "\(camera.name)")
        }
        #expect(Set(CameraCatalog.brands).isSuperset(of: ["Sony", "Canon", "Nikon", "Fujifilm", "Apple"]))
    }

    @Test func spotChecks() throws {
        let d750 = try #require(CameraCatalog.camera(id: "nikon-d750"))
        #expect(abs(d750.pixelPitchMicrons - 5.97) < 0.01)
        #expect(d750.formatName == "Full frame")
        let r4 = try #require(CameraCatalog.camera(id: "sony-a7r-iv"))
        #expect(abs(r4.pixelPitchMicrons - 3.76) < 0.01)
        let xt5 = try #require(CameraCatalog.search("fujifilm x-t5").first)
        #expect(abs(xt5.pixelPitchMicrons - 3.04) < 0.01)
        #expect(xt5.formatName == "APS-C")
        let om1 = try #require(CameraCatalog.search("OM-1 Mark II").first)
        #expect(om1.formatName == "Micro Four Thirds")
        #expect(abs(om1.cropFactor - 2.0) < 0.02)
        // Default CoC = diagonal / 1500.
        #expect(abs(d750.coc - d750.sensor.diagonalMM / 1500) < 1e-12)
        let gfx = try #require(CameraCatalog.search("GFX100 II").first)
        #expect(gfx.formatName == "Medium format")
    }

    @Test func search() {
        #expect(CameraCatalog.search("a7 iv").contains { $0.model == "α7 IV" })
        #expect(Set(CameraCatalog.search("canon r5").map(\.model)) == ["EOS R5", "EOS R5 Mark II", "EOS R50"])
        #expect(CameraCatalog.search("").count == CameraCatalog.bundled.count)
        #expect(CameraCatalog.search("zzz").isEmpty)
    }

    @MainActor
    @Test func storePersistsCustomCamerasAndDefault() throws {
        let suite = "camera-store-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CameraStore(defaults: defaults)
        #expect(store.defaultCamera == CameraCatalog.fallback)
        let mine = Camera(brand: "Mine", model: "Pinhole", sensorWidth: 30, sensorHeight: 20, pixelsWide: 3000, pixelsHigh: 2000,
                          cocOverride: 0.05)
        #expect(store.save(mine))
        #expect(!store.save(Camera(brand: "Bad", model: "", sensorWidth: 0, sensorHeight: 1, pixelsWide: 1, pixelsHigh: 1)))
        store.setDefault(mine)
        store.toggleFavourite(mine)
        let reloaded = CameraStore(defaults: defaults)
        #expect(reloaded.custom.count == 1)
        #expect(reloaded.defaultCamera.model == "Pinhole" && reloaded.defaultCamera.coc == 0.05)
        #expect(reloaded.favourites.contains(mine.id))
        reloaded.delete(mine)
        #expect(CameraStore(defaults: defaults).defaultCamera == CameraCatalog.fallback)
    }
}
