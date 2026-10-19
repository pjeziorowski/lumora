#!/usr/bin/env python3
# Tools/golden/generate_milkyway.py
#
# Golden Milky Way visibility windows for Phase 4: for a few northern and southern dark-sky
# sites, on 2026 new-moon nights through the galactic-centre season, the spans when the
# Sun's geometric centre is below -18 deg AND the galactic centre (l = 0, b = 0, J2000
# 17h45m37.2s -28d56m10s) is above the horizon (apparent, standard refraction).
#
# Reference engine: Skyfield (MIT) + JPL DE421 (skyfield-data). Independent of Astronomy
# Engine, which AstroCore ports. Skyfield's Star applies precession, nutation and annual
# aberration; its refraction is Bennett's formula at 10 C / 1010 mbar.
#
# Usage:  python3 -m pip install skyfield skyfield-data
#         python3 Tools/golden/generate_milkyway.py
# Writes Packages/AstroCore/Tests/AstroCoreTests/Golden/milkyway.json.

import json, os
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import skyfield_data
from skyfield import almanac
from skyfield.api import Star, load, wgs84
from skyfield.jpllib import SpiceKernel

GOLDEN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                      "Packages", "AstroCore", "Tests", "AstroCoreTests", "Golden")
DATA = os.path.join(os.path.dirname(skyfield_data.__file__), "data")
ts = load.timescale(builtin=True)
eph = SpiceKernel(os.path.join(DATA, "de421.bsp"))
earth, sun = eph["earth"], eph["sun"]
GC = Star(ra_hours=(17, 45, 37.2), dec_degrees=(-28, 56, 10.0))

SITES = [
    # name, lat, lon, height m, zone
    ("Joshua Tree",   34.1347, -116.3131,  900, "America/Los_Angeles"),
    ("La Palma",      28.7606,  -17.8816, 2400, "Atlantic/Canary"),
    ("Warsaw",        52.2297,   21.0122,  100, "Europe/Warsaw"),
    ("San Pedro de Atacama", -22.9087, -68.1997, 2400, "America/Santiago"),
    ("Sydney",       -33.8688,  151.2093,   20, "Australia/Sydney"),
]
# Local evening dates of 2026 new moons (USNO: Feb 17, Mar 19, Apr 17, May 16, Jun 15,
# Jul 14, Aug 12, Sep 11, Oct 10, Dec 9).
NIGHTS = ["2026-02-17", "2026-03-19", "2026-04-17", "2026-05-16", "2026-06-15",
          "2026-07-14", "2026-08-12", "2026-09-11", "2026-10-10", "2026-12-09"]


def iso(t):
    return t.utc_datetime().strftime("%Y-%m-%dT%H:%M:%SZ")


def night_windows(lat, lon, height, zone, date):
    tz = ZoneInfo(zone)
    y, m, d = map(int, date.split("-"))
    start = datetime(y, m, d, 12, tzinfo=tz)
    end = start + timedelta(days=1)
    t0, t1 = ts.from_datetime(start), ts.from_datetime(end)
    site = earth + wgs84.latlon(lat, lon, elevation_m=height)

    def ok(t):
        sun_alt = site.at(t).observe(sun).apparent().altaz()[0].degrees
        gc_alt = site.at(t).observe(GC).apparent().altaz("standard")[0].degrees
        return (sun_alt < -18) & (gc_alt > 0)
    ok.step_days = 1 / 288

    times, values = almanac.find_discrete(t0, t1, ok)
    spans = []
    inside = bool(ok(t0))
    begin = t0 if inside else None
    for t, v in zip(times, values):
        if v and not inside:
            begin = t
        elif not v and inside:
            spans.append([iso(begin), iso(t)])
        inside = bool(v)
    if inside:
        spans.append([iso(begin), iso(t1)])
    return spans


def gal_star(l):
    """Point on the galactic equator at longitude l (deg), as a J2000 Star (IAU 1958 frame in ICRS)."""
    from skyfield.framelib import galactic_frame
    import numpy as np
    lr = np.radians(l)
    v = np.array([np.cos(lr), np.sin(lr), 0.0])
    # galactic_frame.rotation_at maps ICRS -> galactic; transpose maps back.
    icrs = galactic_frame.rotation_at(ts.J2000).T.dot(v)
    ra = np.degrees(np.arctan2(icrs[1], icrs[0])) % 360
    dec = np.degrees(np.arcsin(icrs[2]))
    return Star(ra_hours=ra / 15, dec_degrees=dec)


def samples():
    """GC az/alt (apparent, refracted) and arc tilt at a few instants per site."""
    import numpy as np
    out = []
    a_star, b_star = gal_star(-1), gal_star(1)
    for name, lat, lon, height, zone in SITES:
        site = earth + wgs84.latlon(lat, lon, elevation_m=height)
        for stamp in ["2026-03-20T06:00:00Z", "2026-06-16T02:00:00Z", "2026-07-15T08:00:00Z",
                      "2026-08-13T20:00:00Z", "2026-09-11T22:00:00Z"]:
            t = ts.from_datetime(datetime.fromisoformat(stamp.replace("Z", "+00:00")))
            alt, az, _ = site.at(t).observe(GC).apparent().altaz("standard")
            a_alt, a_az, _ = site.at(t).observe(a_star).apparent().altaz()
            b_alt, b_az, _ = site.at(t).observe(b_star).apparent().altaz()
            mid = np.radians((a_alt.degrees + b_alt.degrees) / 2)
            daz = ((b_az.degrees - a_az.degrees + 180) % 360 - 180) * np.cos(mid)
            tilt = np.degrees(np.arctan2(abs(b_alt.degrees - a_alt.degrees), abs(daz)))
            out.append({"site": name, "lat": lat, "lon": lon, "height": height, "time": stamp,
                        "azimuth": round(az.degrees, 4), "altitude": round(alt.degrees, 4),
                        "tilt": round(float(tilt), 3)})
    return out


def main():
    rows = []
    for name, lat, lon, height, zone in SITES:
        for date in NIGHTS:
            rows.append({"site": name, "lat": lat, "lon": lon, "height": height, "zone": zone,
                         "night": date, "visible": night_windows(lat, lon, height, zone, date)})
    out = {"source": "Skyfield %s + JPL DE421; GC = l0 b0 J2000 17h45m37.2s -28d56m10s; "
                     "visible = Sun centre < -18 deg (airless) and GC apparent altitude > 0 deg "
                     "(Bennett refraction, standard atmosphere)" % __import__("skyfield").__version__,
           "nights": rows, "samples": samples()}
    with open(os.path.join(GOLDEN, "milkyway.json"), "w") as f:
        json.dump(out, f, indent=1)
    print("wrote", len(rows), "nights")


if __name__ == "__main__":
    main()
