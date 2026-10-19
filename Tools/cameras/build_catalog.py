#!/usr/bin/env python3
# Tools/cameras/build_catalog.py
#
# Builds Packages/CameraCatalog/Sources/CameraCatalog/Resources/cameras.json from the table
# below. Sensor sizes (mm, to 0.1) and image sizes (pixels) are as published in the
# manufacturers' specification sheets; phone entries are the main (wide) camera and their
# sensor sizes are the nominal optical-format sizes, so they are marked approximate.
# Derived fields (pixel pitch, crop factor, default CoC = diagonal / 1500) are computed by
# the app, not stored.

import json
import os

# brand, model, category, width mm, height mm, pixels wide, pixels high
CAMERAS = [
    # Sony
    ("Sony", "α1", "mirrorless", 35.9, 24.0, 8640, 5760),
    ("Sony", "α9 III", "mirrorless", 35.6, 23.8, 6000, 4000),
    ("Sony", "α9 II", "mirrorless", 35.6, 23.8, 6000, 4000),
    ("Sony", "α7R V", "mirrorless", 35.7, 23.8, 9504, 6336),
    ("Sony", "α7R IV", "mirrorless", 35.7, 23.8, 9504, 6336),
    ("Sony", "α7R III", "mirrorless", 35.9, 24.0, 7952, 5304),
    ("Sony", "α7R II", "mirrorless", 35.9, 24.0, 7952, 5304),
    ("Sony", "α7 IV", "mirrorless", 35.9, 23.9, 7008, 4672),
    ("Sony", "α7 III", "mirrorless", 35.6, 23.8, 6000, 4000),
    ("Sony", "α7 II", "mirrorless", 35.8, 23.9, 6000, 4000),
    ("Sony", "α7", "mirrorless", 35.8, 23.9, 6000, 4000),
    ("Sony", "α7S III", "mirrorless", 35.6, 23.8, 4240, 2832),
    ("Sony", "α7S II", "mirrorless", 35.6, 23.8, 4240, 2832),
    ("Sony", "α7C II", "mirrorless", 35.9, 23.9, 7008, 4672),
    ("Sony", "α7C R", "mirrorless", 35.7, 23.8, 9504, 6336),
    ("Sony", "α7C", "mirrorless", 35.6, 23.8, 6000, 4000),
    ("Sony", "ZV-E1", "mirrorless", 35.6, 23.8, 4240, 2832),
    ("Sony", "α6700", "mirrorless", 23.3, 15.5, 6192, 4128),
    ("Sony", "α6600", "mirrorless", 23.5, 15.6, 6000, 4000),
    ("Sony", "α6400", "mirrorless", 23.5, 15.6, 6000, 4000),
    ("Sony", "α6100", "mirrorless", 23.5, 15.6, 6000, 4000),
    ("Sony", "α6500", "mirrorless", 23.5, 15.6, 6000, 4000),
    ("Sony", "α6000", "mirrorless", 23.5, 15.6, 6000, 4000),
    ("Sony", "ZV-E10", "mirrorless", 23.5, 15.6, 6000, 4000),
    ("Sony", "RX1R II", "compact", 35.9, 24.0, 7952, 5304),
    ("Sony", "RX100 VII", "compact", 13.2, 8.8, 5472, 3648),
    ("Sony", "RX10 IV", "compact", 13.2, 8.8, 5472, 3648),
    # Canon
    ("Canon", "EOS R1", "mirrorless", 36.0, 24.0, 6000, 4000),
    ("Canon", "EOS R3", "mirrorless", 36.0, 24.0, 6000, 4000),
    ("Canon", "EOS R5 Mark II", "mirrorless", 36.0, 24.0, 8192, 5464),
    ("Canon", "EOS R5", "mirrorless", 36.0, 24.0, 8192, 5464),
    ("Canon", "EOS R6 Mark II", "mirrorless", 35.9, 23.9, 6000, 4000),
    ("Canon", "EOS R6", "mirrorless", 35.9, 23.9, 5472, 3648),
    ("Canon", "EOS R8", "mirrorless", 35.9, 23.9, 6000, 4000),
    ("Canon", "EOS R", "mirrorless", 36.0, 24.0, 6720, 4480),
    ("Canon", "EOS RP", "mirrorless", 35.9, 24.0, 6240, 4160),
    ("Canon", "EOS R7", "mirrorless", 22.3, 14.8, 6960, 4640),
    ("Canon", "EOS R10", "mirrorless", 22.3, 14.8, 6000, 4000),
    ("Canon", "EOS R50", "mirrorless", 22.3, 14.9, 6000, 4000),
    ("Canon", "EOS R100", "mirrorless", 22.3, 14.9, 6000, 4000),
    ("Canon", "EOS M50 Mark II", "mirrorless", 22.3, 14.9, 6000, 4000),
    ("Canon", "EOS-1D X Mark III", "dslr", 36.0, 24.0, 5472, 3648),
    ("Canon", "EOS-1D X Mark II", "dslr", 35.9, 23.9, 5472, 3648),
    ("Canon", "EOS 5DS R", "dslr", 36.0, 24.0, 8688, 5792),
    ("Canon", "EOS 5D Mark IV", "dslr", 36.0, 24.0, 6720, 4480),
    ("Canon", "EOS 5D Mark III", "dslr", 36.0, 24.0, 5760, 3840),
    ("Canon", "EOS 5D Mark II", "dslr", 36.0, 24.0, 5616, 3744),
    ("Canon", "EOS 6D Mark II", "dslr", 35.9, 24.0, 6240, 4160),
    ("Canon", "EOS 6D", "dslr", 35.8, 23.9, 5472, 3648),
    ("Canon", "EOS 90D", "dslr", 22.3, 14.8, 6960, 4640),
    ("Canon", "EOS 80D", "dslr", 22.5, 15.0, 6000, 4000),
    ("Canon", "EOS 7D Mark II", "dslr", 22.4, 15.0, 5472, 3648),
    ("Canon", "EOS 7D", "dslr", 22.3, 14.9, 5184, 3456),
    ("Canon", "EOS 850D / Rebel T8i", "dslr", 22.3, 14.9, 6000, 4000),
    ("Canon", "EOS 250D / Rebel SL3", "dslr", 22.3, 14.9, 6000, 4000),
    ("Canon", "EOS 2000D / Rebel T7", "dslr", 22.3, 14.9, 6000, 4000),
    ("Canon", "EOS 700D / Rebel T5i", "dslr", 22.3, 14.9, 5184, 3456),
    ("Canon", "PowerShot G7 X Mark III", "compact", 13.2, 8.8, 5472, 3648),
    # Nikon
    ("Nikon", "Z9", "mirrorless", 35.9, 23.9, 8256, 5504),
    ("Nikon", "Z8", "mirrorless", 35.9, 23.9, 8256, 5504),
    ("Nikon", "Z7 II", "mirrorless", 35.9, 23.9, 8256, 5504),
    ("Nikon", "Z7", "mirrorless", 35.9, 23.9, 8256, 5504),
    ("Nikon", "Z6 III", "mirrorless", 35.9, 23.9, 6048, 4032),
    ("Nikon", "Z6 II", "mirrorless", 35.9, 23.9, 6048, 4024),
    ("Nikon", "Z6", "mirrorless", 35.9, 23.9, 6048, 4024),
    ("Nikon", "Zf", "mirrorless", 35.9, 23.9, 6048, 4032),
    ("Nikon", "Z5 II", "mirrorless", 35.9, 23.9, 6048, 4032),
    ("Nikon", "Z5", "mirrorless", 35.9, 23.9, 6016, 4016),
    ("Nikon", "Z50 II", "mirrorless", 23.5, 15.7, 5568, 3712),
    ("Nikon", "Z50", "mirrorless", 23.5, 15.7, 5568, 3712),
    ("Nikon", "Z fc", "mirrorless", 23.5, 15.7, 5568, 3712),
    ("Nikon", "Z30", "mirrorless", 23.5, 15.7, 5568, 3712),
    ("Nikon", "D6", "dslr", 35.9, 23.9, 5568, 3712),
    ("Nikon", "D5", "dslr", 35.9, 23.9, 5568, 3712),
    ("Nikon", "D4", "dslr", 36.0, 23.9, 4928, 3280),
    ("Nikon", "D850", "dslr", 35.9, 23.9, 8256, 5504),
    ("Nikon", "D810", "dslr", 35.9, 24.0, 7360, 4912),
    ("Nikon", "D800", "dslr", 35.9, 24.0, 7360, 4912),
    ("Nikon", "D780", "dslr", 35.9, 23.9, 6048, 4024),
    ("Nikon", "D750", "dslr", 35.9, 24.0, 6016, 4016),
    ("Nikon", "D610", "dslr", 35.9, 24.0, 6016, 4016),
    ("Nikon", "D500", "dslr", 23.5, 15.7, 5568, 3712),
    ("Nikon", "D7500", "dslr", 23.5, 15.7, 5568, 3712),
    ("Nikon", "D7200", "dslr", 23.5, 15.6, 6000, 4000),
    ("Nikon", "D7100", "dslr", 23.5, 15.6, 6000, 4000),
    ("Nikon", "D5600", "dslr", 23.5, 15.6, 6000, 4000),
    ("Nikon", "D3500", "dslr", 23.5, 15.6, 6000, 4000),
    ("Nikon", "D3200", "dslr", 23.2, 15.4, 6016, 4000),
    # Fujifilm
    ("Fujifilm", "GFX100 II", "mirrorless", 43.8, 32.9, 11648, 8736),
    ("Fujifilm", "GFX100S", "mirrorless", 43.8, 32.9, 11648, 8736),
    ("Fujifilm", "GFX50S II", "mirrorless", 43.8, 32.9, 8256, 6192),
    ("Fujifilm", "X-H2", "mirrorless", 23.5, 15.6, 7728, 5152),
    ("Fujifilm", "X-H2S", "mirrorless", 23.5, 15.6, 6240, 4160),
    ("Fujifilm", "X-T5", "mirrorless", 23.5, 15.6, 7728, 5152),
    ("Fujifilm", "X-T4", "mirrorless", 23.5, 15.6, 6240, 4160),
    ("Fujifilm", "X-T3", "mirrorless", 23.5, 15.6, 6240, 4160),
    ("Fujifilm", "X-T2", "mirrorless", 23.6, 15.6, 6000, 4000),
    ("Fujifilm", "X-T50", "mirrorless", 23.5, 15.6, 7728, 5152),
    ("Fujifilm", "X-T30 II", "mirrorless", 23.5, 15.6, 6240, 4160),
    ("Fujifilm", "X-T30", "mirrorless", 23.5, 15.6, 6240, 4160),
    ("Fujifilm", "X-S20", "mirrorless", 23.5, 15.6, 6240, 4160),
    ("Fujifilm", "X-S10", "mirrorless", 23.5, 15.6, 6240, 4160),
    ("Fujifilm", "X-Pro3", "mirrorless", 23.5, 15.6, 6240, 4160),
    ("Fujifilm", "X-E4", "mirrorless", 23.5, 15.6, 6240, 4160),
    ("Fujifilm", "X-M5", "mirrorless", 23.5, 15.6, 6240, 4160),
    ("Fujifilm", "X100VI", "compact", 23.5, 15.6, 7728, 5152),
    ("Fujifilm", "X100V", "compact", 23.5, 15.6, 6240, 4160),
    # Panasonic
    ("Panasonic", "Lumix S1R", "mirrorless", 36.0, 24.0, 8368, 5584),
    ("Panasonic", "Lumix S1", "mirrorless", 35.6, 23.8, 6000, 4000),
    ("Panasonic", "Lumix S1H", "mirrorless", 35.6, 23.8, 6000, 4000),
    ("Panasonic", "Lumix S5 II", "mirrorless", 35.6, 23.8, 6000, 4000),
    ("Panasonic", "Lumix S5", "mirrorless", 35.6, 23.8, 6000, 4000),
    ("Panasonic", "Lumix S9", "mirrorless", 35.6, 23.8, 6000, 4000),
    ("Panasonic", "Lumix GH7", "mirrorless", 17.3, 13.0, 5776, 4336),
    ("Panasonic", "Lumix GH6", "mirrorless", 17.3, 13.0, 5776, 4336),
    ("Panasonic", "Lumix GH5 II", "mirrorless", 17.3, 13.0, 5184, 3888),
    ("Panasonic", "Lumix GH5", "mirrorless", 17.3, 13.0, 5184, 3888),
    ("Panasonic", "Lumix G9 II", "mirrorless", 17.3, 13.0, 5776, 4336),
    ("Panasonic", "Lumix G9", "mirrorless", 17.3, 13.0, 5184, 3888),
    ("Panasonic", "Lumix G85", "mirrorless", 17.3, 13.0, 4592, 3448),
    ("Panasonic", "Lumix G100", "mirrorless", 17.3, 13.0, 5184, 3888),
    # OM System / Olympus
    ("OM System", "OM-1 Mark II", "mirrorless", 17.4, 13.0, 5184, 3888),
    ("OM System", "OM-1", "mirrorless", 17.4, 13.0, 5184, 3888),
    ("OM System", "OM-5", "mirrorless", 17.4, 13.0, 5184, 3888),
    ("Olympus", "OM-D E-M1 Mark III", "mirrorless", 17.4, 13.0, 5184, 3888),
    ("Olympus", "OM-D E-M1 Mark II", "mirrorless", 17.4, 13.0, 5184, 3888),
    ("Olympus", "OM-D E-M5 Mark III", "mirrorless", 17.4, 13.0, 5184, 3888),
    ("Olympus", "OM-D E-M10 Mark IV", "mirrorless", 17.4, 13.0, 5184, 3888),
    # Leica
    ("Leica", "Q3", "compact", 36.0, 24.0, 9520, 6336),
    ("Leica", "Q2", "compact", 36.0, 24.0, 8368, 5584),
    ("Leica", "M11", "rangefinder", 36.0, 24.0, 9528, 6328),
    ("Leica", "M10", "rangefinder", 35.8, 23.9, 5976, 3992),
    ("Leica", "SL2", "mirrorless", 36.0, 24.0, 8368, 5584),
    # Pentax / Ricoh
    ("Pentax", "K-1 Mark II", "dslr", 35.9, 24.0, 7360, 4912),
    ("Pentax", "K-3 Mark III", "dslr", 23.3, 15.5, 6192, 4128),
    ("Pentax", "K-70", "dslr", 23.5, 15.6, 6000, 4000),
    ("Pentax", "KF", "dslr", 23.5, 15.6, 6000, 4000),
    ("Ricoh", "GR III", "compact", 23.5, 15.6, 6000, 4000),
    # Hasselblad / Sigma
    ("Hasselblad", "X2D 100C", "mirrorless", 43.8, 32.9, 11656, 8742),
    ("Hasselblad", "907X 50C", "mirrorless", 43.8, 32.9, 8272, 6200),
    ("Sigma", "fp L", "mirrorless", 35.9, 23.9, 9520, 6328),
    ("Sigma", "fp", "mirrorless", 35.9, 23.9, 6000, 4000),
    # Drones
    ("DJI", "Mavic 3 (Hasselblad camera)", "drone", 17.3, 13.0, 5280, 3956),
    ("DJI", "Air 3 (wide camera)", "drone", 9.6, 7.2, 8064, 6048),
    ("DJI", "Mini 4 Pro", "drone", 9.6, 7.2, 8064, 6048),
    # Phones (main camera, nominal sensor size)
    ("Apple", "iPhone 16 Pro (main)", "phone", 9.8, 7.3, 8064, 6048),
    ("Apple", "iPhone 15 Pro (main)", "phone", 9.8, 7.3, 8064, 6048),
    ("Apple", "iPhone 14 Pro (main)", "phone", 9.8, 7.3, 8064, 6048),
    ("Google", "Pixel 9 Pro (main)", "phone", 9.8, 7.4, 8160, 6144),
    ("Google", "Pixel 8 Pro (main)", "phone", 9.8, 7.4, 8160, 6144),
    ("Samsung", "Galaxy S24 Ultra (main)", "phone", 9.6, 7.2, 12000, 9000),
]


def slug(brand, model):
    keep = "".join(c.lower() if c.isascii() and c.isalnum() else "-" for c in f"{brand} {model}".replace("α", "a"))
    while "--" in keep:
        keep = keep.replace("--", "-")
    return keep.strip("-")


def main():
    out = []
    seen = set()
    for brand, model, category, w, h, pw, ph in CAMERAS:
        cid = slug(brand, model)
        assert cid not in seen, cid
        seen.add(cid)
        assert w >= h and pw >= ph
        out.append({"id": cid, "brand": brand, "model": model, "category": category,
                    "sensorWidth": w, "sensorHeight": h, "pixelsWide": pw, "pixelsHigh": ph,
                    "approximate": category == "phone"})
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Packages", "CameraCatalog",
                        "Sources", "CameraCatalog", "Resources", "cameras.json")
    with open(path, "w") as f:
        json.dump({"version": 1, "cameras": out}, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print(f"{len(out)} cameras -> {os.path.normpath(path)}")


if __name__ == "__main__":
    main()
