"""KaChat Chess app icon: a game controller in KaChat teal with the backward K (the Kaspa mark)
cut into its middle, a D-pad on the left and four buttons on the right.
`python3 make_chess_icon.py light|dark|tinted` writes kachat-chess-<variant>.svg (all three with
no argument)."""
import sys

PALETTES = {
    #          background  body top / bottom      K and controls  shadow
    "light":  ("#FFFFFF", ("#8AD6C9", "#5BBDAC"), "#FFFFFF", 0.18),
    "dark":   ("#1B2029", ("#8AD6C9", "#5BBDAC"), "#1B2029", 0.45),
    "tinted": ("#000000", ("#EDEDED", "#C4C4C4"), "#000000", 0.5),
}


def k_mark(cx, cy, s, color):
    # the backward K in a 0..90 x -5..105 box, centred on (cx, cy) - the same drawing as
    # KaPosts' and KaChat Wallet's icons
    return (f'<g transform="translate({cx - 45 * s:.1f} {cy - 50 * s:.1f}) scale({s})">'
            f'<polyline points="8,15 61,50 8,85" fill="none" stroke="{color}" stroke-width="17" stroke-miterlimit="4"/>'
            f'<polygon points="60,-3 77,-5 80,50 74,105 56,103 58,50" fill="{color}"/></g>')


def d_pad(cx, cy, color):
    # a plus with rounded ends, 132 across, arms 44 wide
    arm, half = 44, 66
    return (f'<rect x="{cx - half}" y="{cy - arm / 2}" width="{2 * half}" height="{arm}" rx="12" fill="{color}"/>'
            f'<rect x="{cx - arm / 2}" y="{cy - half}" width="{arm}" height="{2 * half}" rx="12" fill="{color}"/>')


def buttons(cx, cy, color):
    # four face buttons in a diamond
    gap, r = 48, 23
    return "".join(f'<circle cx="{cx + dx}" cy="{cy + dy}" r="{r}" fill="{color}"/>'
                   for dx, dy in ((0, -gap), (gap, 0), (0, gap), (-gap, 0)))


# The controller, one closed outline: the top edge, the right grip, the bottom between the grips,
# the left grip. Drawn a little low, then lifted 54 so it sits in the middle of the icon.
CONTROLLER = (
    "M330 300 L694 300 "
    "C800 300 858 336 880 412 "              # top right shoulder
    "C910 512 932 640 924 728 "              # right side
    "C916 806 836 832 786 784 "              # right grip, rounded bottom
    "C748 748 722 696 682 672 "              # right grip, inner edge
    "C604 652 420 652 342 672 "              # bottom between the grips
    "C302 696 276 748 238 784 "              # left grip, inner edge
    "C188 832 108 806 100 728 "              # left grip, rounded bottom
    "C92 640 114 512 144 412 "               # left side
    "C166 336 224 300 330 300 Z"             # top left shoulder
)


def svg(variant):
    bg, (top, bottom), k, shadow = PALETTES[variant]
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="body" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>
    <filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="14" stdDeviation="18" flood-color="#000" flood-opacity="{shadow}"/></filter>
  </defs>
  <rect width="1024" height="1024" fill="{bg}"/>
  <g transform="translate(0 -54)">
  <g filter="url(#soft)"><path d="{CONTROLLER}" fill="url(#body)"/></g>
  {d_pad(262, 470, k)}
  {buttons(762, 470, k)}
  {k_mark(512, 478, 1.75, k)}
  </g>
</svg>'''


if __name__ == "__main__":
    for variant in (sys.argv[1:] or PALETTES):
        open(f"kachat-chess-{variant}.svg", "w").write(svg(variant))
