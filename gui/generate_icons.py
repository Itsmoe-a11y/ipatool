#!/usr/bin/env python3
"""
Generates complete iOS AppIcon asset catalog image set.
"""
import os
import struct
import zlib

def make_png(w, h, filename):
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter type None
        ny = y / float(h)
        for x in range(w):
            nx = x / float(w)
            # Modern iOS Blue & Indigo gradient
            r = int(24 + 18 * ny + 10 * nx)
            g = int(112 + 65 * nx + 10 * ny)
            b = int(230 + 25 * ny)

            # Icon graphics: Stylized white download badge
            cx, cy = (nx - 0.5) * 2.0, (ny - 0.5) * 2.0
            
            # Subtle corner shadow
            if abs(cx) > 0.88 or abs(cy) > 0.88:
                r = int(r * 0.88)
                g = int(g * 0.88)
                b = int(b * 0.88)

            # Download arrow & tray
            is_base = (-0.38 <= cx <= 0.38) and (0.22 <= cy <= 0.32)
            is_stem = (-0.08 <= cx <= 0.08) and (-0.35 <= cy <= 0.08)
            is_head = (0.0 <= cy <= 0.22) and (abs(cx) <= (0.26 - (cy - 0.0) * 0.95))

            if is_base or is_stem or is_head:
                r, g, b = 255, 255, 255

            raw.extend([r, g, b, 255])

    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

    png = (
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(bytes(raw)))
        + chunk(b'IEND', b'')
    )
    with open(filename, 'wb') as f:
        f.write(png)

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    target_dir = os.path.join(script_dir, "Resources", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(target_dir, exist_ok=True)

    sizes = {
        'icon-20.png': (20, 20),
        'icon-20@2x.png': (40, 40),
        'icon-20@3x.png': (60, 60),
        'icon-29.png': (29, 29),
        'icon-29@2x.png': (58, 58),
        'icon-29@3x.png': (87, 87),
        'icon-40.png': (40, 40),
        'icon-40@2x.png': (80, 80),
        'icon-40@3x.png': (120, 120),
        'icon-60@2x.png': (120, 120),
        'icon-60@3x.png': (180, 180),
        'icon-76.png': (76, 76),
        'icon-76@2x.png': (152, 152),
        'icon-83.5@2x.png': (167, 167),
        'icon-1024.png': (1024, 1024),
    }

    for name, (w, h) in sizes.items():
        make_png(w, h, os.path.join(target_dir, name))

    print(f"Generated {len(sizes)} icon sizes in {target_dir}")

if __name__ == "__main__":
    main()
