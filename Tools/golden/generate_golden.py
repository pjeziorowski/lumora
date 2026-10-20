#!/usr/bin/env python3
# Tools/golden/generate_golden.py
#
# Generates the AstroCore golden reference table for the six Phase 1 cities on the
# 2025-2026 solstices and equinoxes.
#
# Reference engine: Skyfield (MIT) + JPL DE421 planetary ephemeris (bundled by the
# `skyfield-data` package). Rise/set uses the USNO definitions documented at
# https://aa.usno.navy.mil/faq/RST_defs (Sun centre at -0.8333 deg; Moon upper limb,
# topocentric, 34' refraction; sea-level observer). Twilights use the Sun's geometric
# centre at -6/-12/-18 deg, also per USNO.
#
# This is an independent implementation from Astronomy Engine (which AstroCore ports),
# so agreement is a real cross-check. USNO's own web API was not reachable from the
# build container; see README in this folder for how to spot-check against it.
#
# Usage:  python3 -m pip install skyfield skyfield-data
#         python3 Tools/golden/generate_golden.py
# Writes cities.json and apsides.json into Packages/AstroCore/Tests/AstroCoreTests/Golden/.

import json, os, sys
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import skyfield_data
from skyfield import almanac
from skyfield.api import load, wgs84
from skyfield.jpllib import SpiceKernel

GOLDEN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                      "Packages", "AstroCore", "Tests", "AstroCoreTests", "Golden")
DATA = os.path.join(os.path.dirname(skyfield_data.__file__), "data")
ts = load.timescale(builtin=True)
eph = SpiceKernel(os.path.join(DATA, "de421.bsp"))
earth, sun, moon = eph["earth"], eph["sun"], eph["moon"]

CITIES = [
    # name, lat, lon, IANA zone
    ("Warsaw",    52.2297,   21.0122, "Europe/Warsaw"),
    ("Reykjavik", 64.1466,  -21.9426, "Atlantic/Reykjavik"),
    ("Tromso",    69.6492,   18.9553, "Europe/Oslo"),
    ("Sydney",   -33.8688,  151.2093, "Australia/Sydney"),
    ("Quito",     -0.1807,  -78.4678, "America/Guayaquil"),
    ("Honolulu",  21.3069, -157.8583, "Pacific/Honolulu"),
]

# UTC calendar dates of the 2025/2026 equinoxes and solstices (USNO seasons table:
# 2025-03-20T09:01Z, 2025-06-21T02:42Z, 2025-09-22T18:19Z, 2025-12-21T15:03Z,
# 2026-03-20T14:46Z, 2026-06-21T08:24Z, 2026-09-23T00:05Z, 2026-12-21T20:50Z).
DATES = ["2025-03-20", "2025-06-21", "2025-09-22", "2025-12-21",
         "2026-03-20", "2026-06-21", "2026-09-23", "2026-12-21"]

# Instants (UTC hours on the date) at which positions are sampled.
SAMPLE_HOURS = [0, 6, 12, 18]


def iso(t):
    return t.utc_datetime().strftime("%Y-%m-%dT%H:%M:%SZ")


def events(f, t0, t1):
    times, values = almanac.find_discrete(t0, t1, f)
    return [(iso(t), bool(v)) for t, v in zip(times, values)]


def rise_set(observer, body, t0, t1):
    r, ry = almanac.find_risings(observer, body, t0, t1)
    s, sy = almanac.find_settings(observer, body, t0, t1)
    rises = [iso(t) for t, ok in zip(r, ry) if ok]
    sets = [iso(t) for t, ok in zip(s, sy) if ok]
    return rises, sets


def crossings(topos, body, deg, t0, t1):
    observer = earth + topos
    def above(t):
        return observer.at(t).observe(body).apparent().altaz()[0].degrees >= deg
    above.step_days = 0.04
    times, values = almanac.find_discrete(t0, t1, above)
    up = [iso(t) for t, v in zip(times, values) if v]
    down = [iso(t) for t, v in zip(times, values) if not v]
    return up, down


def main():
    rows = []
    for name, lat, lon, zone in CITIES:
        topos = wgs84.latlon(lat, lon, elevation_m=0)
        observer = earth + topos
        tz = ZoneInfo(zone)
        for d in DATES:
            y, m, dd = map(int, d.split("-"))
            local0 = datetime(y, m, dd, tzinfo=tz)
            local1 = local0 + timedelta(days=1)
            t0 = ts.from_datetime(local0.astimezone(timezone.utc))
            t1 = ts.from_datetime(local1.astimezone(timezone.utc))
            sun_r, sun_s = rise_set(observer, sun, t0, t1)
            moon_r, moon_s = rise_set(observer, moon, t0, t1)
            tw = {}
            for label, deg in (("civil", -6.0), ("nautical", -12.0), ("astronomical", -18.0)):
                up, down = crossings(topos, sun, deg, t0, t1)
                tw[label] = {"dawn": up, "dusk": down}
            noon = ts.from_datetime((local0 + timedelta(hours=12)).astimezone(timezone.utc))
            sun_noon_alt = observer.at(noon).observe(sun).apparent().altaz()[0].degrees
            samples = []
            for h in SAMPLE_HOURS:
                t = ts.utc(y, m, dd, h)
                for bname, body in (("sun", sun), ("moon", moon)):
                    app = observer.at(t).observe(body).apparent()
                    alt, az, dist = app.altaz()                       # airless, topocentric
                    ralt, raz, _ = app.altaz(temperature_C=10.0, pressure_mbar=1010.0)
                    samples.append({
                        "body": bname, "utc": iso(t),
                        "azimuth": round(az.degrees, 4),
                        "altitudeAirless": round(alt.degrees, 4),
                        "altitudeRefracted": round(ralt.degrees, 4),
                        "distanceKm": round(dist.km, 1),
                    })
                e = earth.at(t)
                frac = e.observe(moon).apparent().fraction_illuminated(sun)
                samples.append({"body": "moonIllumination", "utc": iso(t),
                                "fraction": round(float(frac), 5)})
            rows.append({
                "city": name, "latitude": lat, "longitude": lon, "timeZone": zone,
                "localDate": d,
                "sunRise": sun_r, "sunSet": sun_s,
                "moonRise": moon_r, "moonSet": moon_s,
                "twilight": tw,
                "sunAltitudeAtLocalNoon": round(sun_noon_alt, 3),
                "samples": samples,
            })
    out = open(os.path.join(GOLDEN, "cities.json"), "w")
    json.dump({
        "source": "Skyfield %s + JPL DE421; USNO rise/set definitions (aa.usno.navy.mil/faq/RST_defs)" % __import__("skyfield").__version__,
        "generator": "Tools/golden/generate_golden.py",
        "rows": rows,
    }, out, indent=1)
    out.write("\n")
    out.close()




def apsides(path):
    """Lunar perigees/apogees 2025-2026 (geocentric distance extrema, DE421)."""
    from skyfield.searchlib import find_maxima, find_minima
    def dist(t):
        return earth.at(t).observe(moon).distance().km
    dist.step_days = 1.0
    t0, t1 = ts.utc(2025, 1, 1), ts.utc(2027, 1, 1)
    rows = []
    for kind, finder in (("perigee", find_minima), ("apogee", find_maxima)):
        times, values = finder(t0, t1, dist)
        rows += [{"kind": kind, "utc": iso(t), "distanceKm": round(float(v), 1)} for t, v in zip(times, values)]
    rows.sort(key=lambda r: r["utc"])
    # find_minima/maxima can report one extremum twice when it lands on a step boundary.
    deduped = []
    for r in rows:
        if deduped and deduped[-1]["kind"] == r["kind"]:
            continue
        deduped.append(r)
    rows = deduped
    with open(path, "w") as f:
        json.dump({"source": "Skyfield + JPL DE421 geocentric Moon distance extrema", "rows": rows}, f, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()
    apsides(os.path.join(GOLDEN, "apsides.json"))
