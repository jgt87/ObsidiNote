"""Builds ObsidiNote's icon: a faceted stone in the accent purples with a white N.
One geometry -> icon.svg, favicon.svg, icon-256.png, obsidinote.ico, favicon.ico."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)

# 256-unit design grid
ROCK = [(112, 10), (198, 36), (244, 122), (214, 222), (110, 248), (24, 192), (14, 88)]
CENTER = (136, 116)
FACETS = ["#A78BFA", "#8B5CF6", "#6D28D9", "#5B21B6", "#4C1D95", "#6D28D9", "#7C3AED"]
N_PARTS = [
    [(80, 82), (102, 82), (102, 186), (80, 186)],      # left stem
    [(154, 82), (176, 82), (176, 186), (154, 186)],    # right stem
    [(80, 82), (102, 82), (176, 186), (154, 186)],     # diagonal
]
WHITE = "#FFFFFF"

def pts(poly):
    return " ".join(f"{x},{y}" for x, y in poly)

facet_polys = []
for i, color in enumerate(FACETS):
    a, b = ROCK[i], ROCK[(i + 1) % len(ROCK)]
    facet_polys.append(([a, b, CENTER], color))

svg = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" role="img" aria-label="ObsidiNote">',
       '  <title>ObsidiNote</title>']
for poly, color in facet_polys:
    svg.append(f'  <polygon points="{pts(poly)}" fill="{color}" stroke="{color}" stroke-width="1" stroke-linejoin="round"/>')
for part in N_PARTS:
    svg.append(f'  <polygon points="{pts(part)}" fill="{WHITE}"/>')
svg.append('</svg>')
text = "\n".join(svg) + "\n"
(out / "icon.svg").write_text(text, encoding="utf-8", newline="\n")
(out / "favicon.svg").write_text(text, encoding="utf-8", newline="\n")

def render(size):
    scale = 4  # supersample, then downscale for smooth edges
    big = 256 * scale
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = lambda poly: [(x * scale, y * scale) for x, y in poly]
    for poly, color in facet_polys:
        d.polygon(s(poly), fill=color, outline=color)
    for part in N_PARTS:
        d.polygon(s(part), fill=WHITE)
    return img.resize((size, size), Image.LANCZOS)

master = render(256)
master.save(out / "icon-256.png")
master.save(out / "obsidinote.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
master.save(out / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])
for f in sorted(out.iterdir()):
    print(f.name, f.stat().st_size)
