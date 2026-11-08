#!/usr/bin/env python3
"""MorningVault app icon directions, drawn with PIL at 4x and downsampled."""
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops
import os

S = 1024
SS = 4
N = S * SS
OUT = os.path.dirname(os.path.abspath(__file__))
NY = "/System/Library/Fonts/NewYork.ttf"


def hexc(h, a=255):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def vgrad(size, stops):
    """Vertical gradient; stops = [(pos0..1, hex)]."""
    w, h = size
    img = Image.new("RGBA", (1, h))
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if p0 <= t <= p1:
                u = (t - p0) / (p1 - p0) if p1 > p0 else 0
                a = hexc(c0); b = hexc(c1)
                px[0, y] = tuple(int(a[k] + (b[k] - a[k]) * u) for k in range(4))
                break
    return img.resize((w, h))


def radial_glow(size, center, r_in, r_out, color, a_in, a_out=0):
    w, h = size
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(glow)
    steps = 48
    for i in range(steps, 0, -1):
        t = i / steps
        r = r_in + (r_out - r_in) * t
        a = int(a_in * (1 - t) ** 1.6)
        d.ellipse([center[0] - r, center[1] - r, center[0] + r, center[1] + r], fill=color + (a,))
    return glow.filter(ImageFilter.GaussianBlur(r_out * 0.08))


def sun(size, center, r, core="#FFF9DF", edge="#F3B364", halo="#F3A24A", halo_a=120, halo_mult=3.2):
    w, h = size
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    layer.alpha_composite(radial_glow(size, center, r * 0.9, r * halo_mult, hexc(halo)[:3], halo_a))
    # disc with radial core->edge
    disc = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(disc)
    steps = 40
    for i in range(steps, 0, -1):
        t = i / steps
        rr = r * t
        a = hexc(core); b = hexc(edge)
        c = tuple(int(a[k] + (b[k] - a[k]) * (t ** 1.4)) for k in range(3)) + (255,)
        d.ellipse([center[0] - rr, center[1] - rr, center[0] + rr, center[1] + rr], fill=c)
    layer.alpha_composite(disc)
    return layer


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m


def finish(img, name):
    out = img.resize((S, S), Image.LANCZOS)
    out.save(os.path.join(OUT, f"{name}.png"))
    return out


# ---------- A. Dawn: sun rising behind a horizon hairline on the warm canvas ----------
def icon_dawn():
    size = (N, N)
    bg = vgrad(size, [(0, "#CFC9DE"), (0.42, "#F1C7A6"), (0.72, "#F7E3C9"), (1, "#F6F2EC")])
    img = bg.convert("RGBA")
    horizon = int(N * 0.66)
    c = (N // 2, horizon)
    r = int(N * 0.19)
    s = sun(size, c, r, halo_a=150, halo_mult=3.6)
    # clip the sun below the horizon: ground is the warm canvas
    img.alpha_composite(s)
    ground = Image.new("RGBA", size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(ground)
    gd.rectangle([0, horizon, N, N], fill=hexc("#F6F2EC"))
    # ground keeps a faint warm reflection
    refl = vgrad((N, N - horizon), [(0, "#F3D9BF"), (1, "#F6F2EC")]).convert("RGBA")
    ground.paste(refl, (0, horizon))
    img.alpha_composite(ground)
    d = ImageDraw.Draw(img)
    d.line([(0, horizon), (N, horizon)], fill=hexc("#171615", 46), width=int(N * 0.004))
    return finish(img, "A_dawn")


# ---------- B. Keyhole aperture, refined: dawn sky seen through the vault ----------
def icon_keyhole():
    size = (N, N)
    img = Image.new("RGBA", size, hexc("#17141B"))
    sky = vgrad(size, [(0, "#2B2749"), (0.35, "#7A5C86"), (0.58, "#E9A878"), (0.8, "#F7E0C2"), (1, "#F6F2EC")]).convert("RGBA")
    sky.alpha_composite(sun(size, (int(N * 0.5), int(N * 0.60)), int(N * 0.10), halo_a=170, halo_mult=3.0))
    # keyhole mask: circle head + tapered stem
    m = Image.new("L", size, 0)
    md = ImageDraw.Draw(m)
    cx, cy = N // 2, int(N * 0.42)
    R = int(N * 0.17)
    md.ellipse([cx - R, cy - R, cx + R, cy + R], fill=255)
    top_w, bot_w = int(N * 0.075), int(N * 0.16)
    bottom = int(N * 0.79)
    md.polygon([(cx - top_w, cy + int(R * 0.55)), (cx + top_w, cy + int(R * 0.55)), (cx + bot_w, bottom), (cx - bot_w, bottom)], fill=255)
    # soften the aperture edge slightly and add an inner rim
    aperture = Image.new("RGBA", size, (0, 0, 0, 0))
    aperture.paste(sky, (0, 0), m)
    # rim: thin lighter stroke around the aperture (dilate mask minus mask)
    dil = m.filter(ImageFilter.MaxFilter(int(N * 0.006) | 1))
    rim = ImageChops.subtract(dil, m)
    rim_layer = Image.new("RGBA", size, hexc("#E2A060", 110))
    # outer bloom from the aperture into the dark
    bloom = Image.new("RGBA", size, (0, 0, 0, 0))
    bloom.paste(Image.new("RGBA", size, hexc("#F3A24A", 140)), (0, 0), m.filter(ImageFilter.GaussianBlur(N * 0.05)))
    img.alpha_composite(bloom)
    img.alpha_composite(aperture)
    img.paste(rim_layer, (0, 0), rim)
    return finish(img, "B_keyhole")


# ---------- C. Monogram: serif M, sun rising in its valley ----------
def icon_monogram():
    size = (N, N)
    img = vgrad(size, [(0, "#F8F4EE"), (1, "#F1E8DC")]).convert("RGBA")
    font = ImageFont.truetype(NY, int(N * 0.62))
    d = ImageDraw.Draw(img)
    bbox = d.textbbox((0, 0), "M", font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = (N - tw) // 2 - bbox[0]
    y = (N - th) // 2 - bbox[1] + int(N * 0.03)
    # sun sits in the M's valley, behind the letter
    valley = (N // 2, y + bbox[1] + int(th * 0.30))
    img.alpha_composite(sun(size, valley, int(N * 0.085), halo_a=150, halo_mult=4.0))
    d = ImageDraw.Draw(img)
    d.text((x, y), "M", font=font, fill=hexc("#171615"))
    return finish(img, "C_monogram")


# ---------- D. Hero: the app's sky card, dawn, one crisp cloud ----------
def icon_hero():
    size = (N, N)
    img = vgrad(size, [(0, "#C7C2DA"), (0.5, "#F1C2A0"), (1, "#F7E0C2")]).convert("RGBA")
    img.alpha_composite(sun(size, (int(N * 0.70), int(N * 0.40)), int(N * 0.13), halo_a=150, halo_mult=3.4))
    # cloud silhouette: union of circles + flat base, lit top / shaded base
    cl = Image.new("L", size, 0)
    cd = ImageDraw.Draw(cl)
    cx, cy, w = int(N * 0.44), int(N * 0.66), int(N * 0.70)
    lobes = [(0.50, 0.31, 0.18), (0.35, 0.36, 0.15), (0.64, 0.35, 0.14), (0.42, 0.27, 0.11), (0.57, 0.26, 0.10),
             (0.28, 0.33, 0.09), (0.73, 0.34, 0.09), (0.20, 0.41, 0.11), (0.81, 0.41, 0.10), (0.50, 0.41, 0.16),
             (0.33, 0.42, 0.14), (0.68, 0.42, 0.13)]
    ox, oy = cx - w // 2, cy - int(w * 0.40)
    for lx, ly, lr in lobes:
        r = lr * w
        cd.ellipse([ox + lx * w - r, oy + ly * w - r, ox + lx * w + r, oy + ly * w + r], fill=255)
    base_y = oy + int(0.52 * w)
    cd.rectangle([0, base_y, N, N], fill=0)  # flat base
    body = vgrad(size, [(0, "#FFFFFF"), (0.45, "#FFFFFF"), (0.75, "#E6E1E8"), (1, "#C9C0CC")]).convert("RGBA")
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", size, hexc("#6E5A6A", 90)), (0, int(N * 0.02)), cl.filter(ImageFilter.GaussianBlur(N * 0.015)))
    img.alpha_composite(shadow)
    cloud = Image.new("RGBA", size, (0, 0, 0, 0))
    cloud.paste(body, (0, 0), cl)
    img.alpha_composite(cloud)
    return finish(img, "D_hero")


def sheet(names):
    """Contact sheet: each icon with the iOS mask at 180, 60 and 29 px equivalents plus full."""
    tile = 420
    pad = 40
    W = tile * len(names) + pad * (len(names) + 1)
    H = 760
    sh = Image.new("RGB", (W, H), (236, 232, 226))
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 28)
    for i, n in enumerate(names):
        ic = Image.open(os.path.join(OUT, n + ".png")).convert("RGBA")
        x0 = pad + i * (tile + pad)
        big = ic.resize((tile, tile), Image.LANCZOS)
        big.putalpha(rounded_mask((tile, tile), int(tile * 0.2237)))
        sh.paste(big, (x0, pad), big)
        y = pad + tile + 40
        xx = x0
        for s in (180, 120, 60, 29):
            sm = ic.resize((s, s), Image.LANCZOS)
            sm.putalpha(rounded_mask((s, s), int(s * 0.2237)))
            sh.paste(sm, (xx, y + (180 - s) // 2), sm)
            xx += s + 20
        ImageDraw.Draw(sh).text((x0, y + 200), n.replace("_", "  "), fill=(40, 38, 36), font=font)
    sh.save(os.path.join(OUT, "sheet.png"))



# ---------- A2. Dawn, refined: bigger sun, crisp rim, deliberate horizon, deeper ground ----------
def icon_dawn2(dark=False):
    size = (N, N)
    if dark:
        bg = vgrad(size, [(0, "#17141B"), (0.40, "#3A2A44"), (0.62, "#8C4F3A"), (0.70, "#D9814A")])
        ground_top, ground_bot, line = "#3A2A2A", "#17141B", "#F3D9BA"
        core, edge, halo = "#FFF4DC", "#F2A24E", "#E8824F"
    else:
        bg = vgrad(size, [(0, "#C9C3DC"), (0.38, "#EDB998"), (0.70, "#F5D4B0")])
        ground_top, ground_bot, line = "#E9D7C3", "#F3EBE0", "#171615"
        core, edge, halo = "#FFF9DF", "#F0A34C", "#E8893A"
    img = bg.convert("RGBA")
    horizon = int(N * 0.70)
    c = (N // 2, horizon)
    r = int(N * 0.235)
    img.alpha_composite(sun(size, c, r, core=core, edge=edge, halo=halo, halo_a=110 if dark else 95, halo_mult=2.6))
    # crisp rim on the disc so the small sizes keep an edge
    d = ImageDraw.Draw(img)
    d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], outline=hexc("#D9742E" if not dark else "#FFB071", 200), width=int(N * 0.006))
    ground = Image.new("RGBA", size, (0, 0, 0, 0))
    refl = vgrad((N, N - horizon), [(0, ground_top), (1, ground_bot)]).convert("RGBA")
    ground.paste(refl, (0, horizon))
    img.alpha_composite(ground)
    d = ImageDraw.Draw(img)
    lw = int(N * 0.009)   # ~2.5 px at 29 px
    d.line([(0, horizon), (N, horizon)], fill=hexc(line, 190 if dark else 200), width=lw)
    return finish(img, "A2_dawn_dark" if dark else "A2_dawn")


# ---------- B2. Keyhole, redrawn: narrow stem, large mark, dawn inside the aperture, no blur ----------
def icon_keyhole2():
    size = (N, N)
    img = Image.new("RGBA", size, hexc("#17141B"))
    sky = vgrad(size, [(0, "#3B3160"), (0.40, "#9A6A8A"), (0.62, "#EDA072"), (0.82, "#F7DFC0"), (1, "#F6F2EC")]).convert("RGBA")
    cx = N // 2
    R = int(N * 0.215)
    cy = int(N * 0.40)
    sky.alpha_composite(sun(size, (cx, cy + int(R * 0.15)), int(R * 0.42), halo_a=120, halo_mult=2.4))
    m = Image.new("L", size, 0)
    md = ImageDraw.Draw(m)
    md.ellipse([cx - R, cy - R, cx + R, cy + R], fill=255)
    neck = int(R * 0.36)
    foot = int(R * 0.62)
    bottom = int(N * 0.82)
    md.polygon([(cx - neck, cy + int(R * 0.70)), (cx + neck, cy + int(R * 0.70)), (cx + foot, bottom), (cx - foot, bottom)], fill=255)
    # round the foot corners by drawing a capsule at the bottom
    md.rounded_rectangle([cx - foot, bottom - int(R * 0.25), cx + foot, bottom], radius=int(R * 0.12), fill=255)
    aperture = Image.new("RGBA", size, (0, 0, 0, 0))
    aperture.paste(sky, (0, 0), m)
    img.alpha_composite(aperture)
    # solid warm contour, thick enough to survive 29 px
    dil = m.filter(ImageFilter.MaxFilter(int(N * 0.012) | 1))
    rim = ImageChops.subtract(dil, m)
    img.paste(Image.new("RGBA", size, hexc("#E2A060")), (0, 0), rim)
    return finish(img, "B2_keyhole")



# ---------- A3. Dawn seen through the vault: the sunrise inside a round aperture with a steel ring ----------
def icon_dawn_vault():
    size = (N, N)
    img = Image.new("RGBA", size, hexc("#17141B"))
    # subtle vignette so the tile is not flat
    img.alpha_composite(radial_glow(size, (N // 2, int(N * 0.5)), 0, int(N * 0.75), hexc("#2A2230")[:3], 120))
    # scene inside the aperture
    scene = vgrad(size, [(0, "#2B2749"), (0.35, "#4A3558"), (0.58, "#B45A3E"), (0.66, "#E9924F")]).convert("RGBA")
    R = int(N * 0.335)
    cx, cy = N // 2, N // 2
    horizon = cy + int(R * 0.22)
    sr = int(R * 0.62)
    scene.alpha_composite(sun(size, (cx, horizon), sr, core="#FFF4DC", edge="#F2A24E", halo="#E8824F", halo_a=120, halo_mult=2.4))
    d = ImageDraw.Draw(scene)
    d.ellipse([cx - sr, horizon - sr, cx + sr, horizon + sr], outline=hexc("#FFB071", 200), width=int(N * 0.006))
    ground = vgrad((N, N - horizon), [(0, "#2A1F22"), (1, "#17141B")]).convert("RGBA")
    scene.paste(ground, (0, horizon))
    d = ImageDraw.Draw(scene)
    d.line([(0, horizon), (N, horizon)], fill=hexc("#F7E3C9", 230), width=int(N * 0.009))
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).ellipse([cx - R, cy - R, cx + R, cy + R], fill=255)
    aperture = Image.new("RGBA", size, (0, 0, 0, 0))
    aperture.paste(scene, (0, 0), m)
    img.alpha_composite(aperture)
    # the vault ring: a thick warm-metal ring with a lit top edge and shaded bottom
    ring_w = int(N * 0.045)
    ring = Image.new("RGBA", size, (0, 0, 0, 0))
    rm = Image.new("L", size, 0)
    rd = ImageDraw.Draw(rm)
    rd.ellipse([cx - R - ring_w, cy - R - ring_w, cx + R + ring_w, cy + R + ring_w], fill=255)
    rd.ellipse([cx - R, cy - R, cx + R, cy + R], fill=0)
    metal = vgrad(size, [(0, "#E9C9A6"), (0.5, "#B8865C"), (1, "#5E4232")]).convert("RGBA")
    ring.paste(metal, (0, 0), rm)
    img.alpha_composite(ring)
    # thin inner highlight line on the ring's inner edge
    d = ImageDraw.Draw(img)
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=hexc("#F3D9BA", 150), width=int(N * 0.004))
    return finish(img, "A3_dawn_vault")


if __name__ == "__main__":
    icon_dawn2(dark=True); icon_dawn_vault()
    print("done")
