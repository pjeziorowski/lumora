// Packages/AstroCore/Sources/AstroCore/Search.swift
//
// Root finder for ascending zero crossings. Port of Astronomy Engine `Astronomy_Search`
// and `QuadInterp`.

import Foundation

enum Search {
    /// Finds the time in [t1, t2] where `f` crosses zero going from negative to non-negative.
    /// Returns nil if no unique ascending root is bracketed or the search does not converge.
    static func ascendingRoot(
        _ t1In: AstroTime, _ t2In: AstroTime, toleranceSeconds: Double, _ f: (AstroTime) -> Double
    ) -> AstroTime? {
        var t1 = t1In, t2 = t2In
        let dtDays = abs(toleranceSeconds / AstroConstants.secondsPerDay)
        var f1 = f(t1)
        var f2 = f(t2)
        var fmid = 0.0
        var calcFmid = true

        for _ in 0..<20 {
            let dt = (t2.tt - t1.tt) / 2.0
            let tmid = t1.addingDays(dt)
            if abs(dt) < dtDays { return tmid }

            if calcFmid { fmid = f(tmid) } else { calcFmid = true }

            if let (qUt, qDfDt) = quadInterp(tmid.ut, t2.ut - tmid.ut, f1, fmid, f2) {
                let tq = AstroTime(ut: qUt)
                let fq = f(tq)
                if qDfDt != 0 {
                    var dtGuess = abs(fq / qDfDt)
                    if dtGuess < dtDays { return tq }
                    // Try a tighter boundary with the interpolated root at the centre.
                    dtGuess *= 1.2
                    if dtGuess < dt / 10.0 {
                        let tleft = tq.addingDays(-dtGuess)
                        let tright = tq.addingDays(+dtGuess)
                        if (tleft.ut - t1.ut) * (tleft.ut - t2.ut) < 0,
                           (tright.ut - t1.ut) * (tright.ut - t2.ut) < 0 {
                            let fleft = f(tleft), fright = f(tright)
                            if fleft < 0, fright >= 0 {
                                f1 = fleft; f2 = fright
                                t1 = tleft; t2 = tright
                                fmid = fq
                                calcFmid = false
                                continue
                            }
                        }
                    }
                }
            }

            if f1 < 0, fmid >= 0 {
                t2 = tmid; f2 = fmid
                continue
            }
            if fmid < 0, f2 >= 0 {
                t1 = tmid; f1 = fmid
                continue
            }
            return nil
        }
        return nil
    }

    /// Fits a parabola through (tm-dt, fa), (tm, fm), (tm+dt, fb) and returns its unique root
    /// in the interval and the slope there. Port of `QuadInterp`.
    static func quadInterp(_ tm: Double, _ dt: Double, _ fa: Double, _ fm: Double, _ fb: Double) -> (Double, Double)? {
        let q = (fb + fa) / 2.0 - fm
        let r = (fb - fa) / 2.0
        let s = fm
        let x: Double
        if q == 0 {
            if r == 0 { return nil }
            x = -s / r
            if x < -1 || x > 1 { return nil }
        } else {
            let u = r * r - 4 * q * s
            if u <= 0 { return nil }
            let ru = u.squareRoot()
            let x1 = (-r + ru) / (2.0 * q)
            let x2 = (-r - ru) / (2.0 * q)
            if -1 <= x1, x1 <= 1 {
                if -1 <= x2, x2 <= 1 { return nil }
                x = x1
            } else if -1 <= x2, x2 <= 1 {
                x = x2
            } else {
                return nil
            }
        }
        return (tm + x * dt, (2 * q * x + r) / dt)
    }
}
