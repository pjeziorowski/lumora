// App/Sources/Planner/ElevationClient.swift
//
// Ground elevation from the free Open-Meteo Elevation API (Copernicus DEM GLO-90, ~90 m
// grid). GeoCore's ElevationService caches the answers; this file only makes the request.

import Foundation

enum ElevationClient {
    struct Response: Decodable {
        let elevation: [Double]
    }

    static func elevation(latitude: Double, longitude: Double) async -> Double? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/elevation")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.5f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.5f", longitude)),
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(Response.self, from: data).elevation.first
        } catch {
            return nil
        }
    }
}
