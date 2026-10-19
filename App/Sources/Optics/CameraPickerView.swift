// App/Sources/Optics/CameraPickerView.swift
//
// Camera picker: search the bundled catalogue, favourites and custom cameras; set the
// default camera; add or edit a custom body (sensor size, resolution, optional CoC).

import CameraCatalog
import SwiftUI

struct CameraPickerView: View {
    @Environment(CameraStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    /// False when the list is the camera manager (Tools → Cameras): picking sets the default.
    var dismissOnPick = true
    @State private var query = ""
    @State private var editing: Camera?

    var body: some View {
        let results = CameraCatalog.search(query, in: store.all)
        List {
            if query.isEmpty {
                let favourites = store.all.filter { store.favourites.contains($0.id) }
                if !favourites.isEmpty {
                    Section("Favourites") { ForEach(favourites) { row($0) } }
                }
                Section("My cameras") {
                    ForEach(store.custom) { row($0) }
                    Button {
                        editing = Camera(brand: "", model: "", sensorWidth: 36, sensorHeight: 24, pixelsWide: 6000, pixelsHigh: 4000)
                    } label: {
                        Label("Add a camera", systemImage: "plus")
                    }
                    .accessibilityIdentifier("camera.add")
                }
                ForEach(CameraCatalog.brands, id: \.self) { brand in
                    Section(brand) {
                        ForEach(results.filter { $0.brand == brand && $0.category != .custom }) { row($0) }
                    }
                }
            } else {
                ForEach(results) { row($0) }
            }
        }
        .searchable(text: $query, prompt: "Brand or model")
        .navigationTitle("Cameras")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { camera in
            NavigationStack {
                CustomCameraForm(camera: camera) { saved in
                    store.save(saved)
                    selection = saved.id
                }
            }
        }
    }

    private func row(_ camera: Camera) -> some View {
        Button {
            selection = camera.id
            if dismissOnPick { dismiss() }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(camera.name).foregroundStyle(.primary)
                    Text(details(camera)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if camera.id == selection { Image(systemName: "checkmark").foregroundStyle(.tint) }
                if camera.id == store.defaultID { Text("Default").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .accessibilityIdentifier("camera.\(camera.id)")
        .swipeActions(edge: .leading) {
            Button {
                store.toggleFavourite(camera)
            } label: {
                Label("Favourite", systemImage: store.favourites.contains(camera.id) ? "star.slash" : "star")
            }
            .tint(.yellow)
            Button {
                store.setDefault(camera)
            } label: {
                Label("Default", systemImage: "checkmark.seal")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing) {
            if camera.category == .custom {
                Button(role: .destructive) { store.delete(camera) } label: { Label("Delete", systemImage: "trash") }
                Button { editing = camera } label: { Label("Edit", systemImage: "pencil") }
            }
        }
    }

    private func details(_ camera: Camera) -> String {
        let size = String(format: "%.1f × %.1f mm", camera.sensorWidth, camera.sensorHeight)
        let mp = String(format: "%.0f MP", camera.sensor.megapixels)
        let pitch = String(format: "%.2f µm", camera.pixelPitchMicrons)
        return "\(camera.formatName) · \(size) · \(mp) · \(pitch)\(camera.approximate ? " · approx." : "")"
    }
}

private struct CustomCameraForm: View {
    @Environment(\.dismiss) private var dismiss
    @State var camera: Camera
    @State private var useCustomCoC = false
    let onSave: (Camera) -> Void

    init(camera: Camera, onSave: @escaping (Camera) -> Void) {
        _camera = State(initialValue: camera)
        _useCustomCoC = State(initialValue: camera.cocOverride != nil)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section {
                TextField("Brand", text: $camera.brand)
                TextField("Model", text: $camera.model)
            }
            Section("Sensor") {
                NumberRow(label: "Width", value: $camera.sensorWidth, unit: "mm", step: 0.1, range: 1...60, decimals: 1)
                NumberRow(label: "Height", value: $camera.sensorHeight, unit: "mm", step: 0.1, range: 1...60, decimals: 1)
                NumberRow(label: "Pixels wide", value: intBinding(\.pixelsWide), step: 100, range: 100...20_000)
                NumberRow(label: "Pixels high", value: intBinding(\.pixelsHigh), step: 100, range: 100...20_000)
            }
            Section {
                Toggle("Custom circle of confusion", isOn: $useCustomCoC)
                if useCustomCoC {
                    NumberRow(label: "CoC", value: Binding(
                        get: { camera.cocOverride ?? camera.sensor.defaultCoC },
                        set: { camera.cocOverride = $0 }
                    ), unit: "mm", step: 0.001, range: 0.001...0.2, decimals: 3)
                }
            } footer: {
                Text("Default: sensor diagonal ÷ 1500 = \(String(format: "%.4f", camera.sensor.defaultCoC)) mm. "
                     + "Pixel pitch \(String(format: "%.2f", camera.pixelPitchMicrons)) µm.")
            }
        }
        .navigationTitle(camera.model.isEmpty ? "New camera" : camera.model)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var saved = camera
                    if !useCustomCoC { saved.cocOverride = nil }
                    if saved.brand.isEmpty { saved.brand = String(localized: "Custom") }
                    onSave(saved)
                    dismiss()
                }
                .disabled(!camera.isValid)
            }
        }
    }

    private func intBinding(_ key: WritableKeyPath<Camera, Int>) -> Binding<Double> {
        Binding(get: { Double(camera[keyPath: key]) }, set: { camera[keyPath: key] = Int($0.rounded()) })
    }
}

/// Tools → Cameras: the same list, where picking a camera makes it the default.
struct CameraManagerView: View {
    @Environment(CameraStore.self) private var store

    var body: some View {
        CameraPickerView(selection: Binding {
            store.defaultID
        } set: { id in
            if let camera = store.camera(id: id) { store.setDefault(camera) }
        }, dismissOnPick: false)
    }
}
