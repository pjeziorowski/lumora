// Packages/AstroCore/Sources/AstroCore/Seasons.swift
//
// Equinoxes and solstices. Ports of Astronomy Engine `Astronomy_SearchSunLongitude`,
// `FindSeasonChange` and `Astronomy_Seasons`.

import Foundation

public struct SeasonInfo: Sendable, Hashable {
    public let marchEquinox: AstroTime
    public let juneSolstice: AstroTime
    public let septemberEquinox: AstroTime
    public let decemberSolstice: AstroTime
}

public enum Seasons {
    /// Finds when the Sun's apparent ecliptic longitude reaches `targetLon` degrees.
    public static func searchSunLongitude(_ targetLon: Double, start: AstroTime, limitDays: Double) -> AstroTime? {
        Search.ascendingRoot(start, start.addingDays(limitDays), toleranceSeconds: 0.01) {
            longitudeOffset(Ephemeris.sunPosition(at: $0).longitude - targetLon)
        }
    }

    /// Equinox and solstice instants for a calendar year. Returns nil only if a search fails,
    /// which does not happen for years 1700–2200 (tested 1900–2100 against USNO).
    public static func of(year: Int) -> SeasonInfo? {
        func find(_ lon: Double, _ month: Int) -> AstroTime? {
            searchSunLongitude(lon, start: AstroTime(year: year, month: month, day: 10), limitDays: 20)
        }
        guard let mar = find(0, 3), let jun = find(90, 6), let sep = find(180, 9), let dec = find(270, 12) else {
            return nil
        }
        return SeasonInfo(marchEquinox: mar, juneSolstice: jun, septemberEquinox: sep, decemberSolstice: dec)
    }
}
