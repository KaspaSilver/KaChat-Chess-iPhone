"""KaChat Chess app icon: a chess king in KaChat teal with the backward K (the Kaspa mark) cut
into its body, standing on a strip of board. `python3 make_chess_icon.py light|dark|tinted`
writes kachat-chess-<variant>.svg (all three with no argument)."""
import sys

PALETTES = {
    #          background  piece top / bottom     board (light, dark squares)   K          shadow
    "light":  ("#FFFFFF", ("#8AD6C9", "#5BBDAC"), ("#D3EFE9", "#A6DDD3"), "#FFFFFF", 0.18),
    "dark":   ("#1B2029", ("#8AD6C9", "#5BBDAC"), ("#2A4B47", "#3F7F75"), "#1B2029", 0.45),
    "tinted": ("#000000", ("#EDEDED", "#C4C4C4"), ("#4D4D4D", "#8C8C8C"), "#000000", 0.5),
}


def k_mark(cx, cy, s, color):
    # the backward K in a 0..90 x -5..105 box, centred on (cx, cy) - the same drawing as
    # KaPosts' and KaChat Wallet's icons
    return (f'<g transform="translate({cx - 45 * s:.1f} {cy - 50 * s:.1f}) scale({s})">'
            f'<polyline points="8,15 61,50 8,85" fill="none" stroke="{color}" stroke-width="17" stroke-miterlimit="4"/>'
            f'<polygon points="60,-3 77,-5 80,50 74,105 56,103 58,50" fill="{color}"/></g>')


def board(light, dark):
    # one row of eight squares under the king, fading out to the sides
    squares = []
    size, top, left = 104, 812, 96
    for i in range(8):
        squares.append(f'<rect x="{left + i * size}" y="{top}" width="{size}" height="{size}" fill="{light if i % 2 == 0 else dark}"/>')
    return (f'<g mask="url(#fade)">{"".join(squares)}</g>')


# The king, one closed outline: cross, crown, collar, body flaring to the base.
KING = (
    "M482 88 h60 a10 10 0 0 1 10 10 v46 h46 a10 10 0 0 1 10 10 v44 a10 10 0 0 1 -10 10 h-46 v34 "
    "C660 252 704 282 690 330 C680 366 652 382 640 392 "        # crown, right side
    "L640 420 L612 420 "                                          # collar, right
    "C614 560 652 690 724 760 "                                   # body, right flank
    "L760 760 a14 14 0 0 1 14 14 v42 a14 14 0 0 1 -14 14 L264 830 a14 14 0 0 1 -14 -14 v-42 a14 14 0 0 1 14 -14 L300 760 "
    "C372 690 410 560 412 420 "                                   # body, left flank
    "L384 420 L384 392 "                                          # collar, left
    "C372 382 344 366 334 330 C320 282 364 252 472 242 "          # crown, left side
    "v-34 h-46 a10 10 0 0 1 -10 -10 v-44 a10 10 0 0 1 10 -10 h46 v-46 a10 10 0 0 1 10 -10 Z"
)


def svg(variant):
    bg, (top, bottom), (light, dark), k, shadow = PALETTES[variant]
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="piece" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>
    <linearGradient id="fadeGradient" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset="0.3" stop-color="#fff" stop-opacity="1"/>
      <stop offset="0.7" stop-color="#fff" stop-opacity="1"/><stop offset="1" stop-color="#fff" stop-opacity="0"/>
    </linearGradient>
    <mask id="fade"><rect x="0" y="0" width="1024" height="1024" fill="url(#fadeGradient)"/></mask>
    <filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="14" stdDeviation="18" flood-color="#000" flood-opacity="{shadow}"/></filter>
  </defs>
  <rect width="1024" height="1024" fill="{bg}"/>
  {board(light, dark)}
  <g filter="url(#soft)"><path d="{KING}" fill="url(#piece)"/></g>
  {k_mark(508, 598, 2.2, k)}
</svg>'''


if __name__ == "__main__":
    for variant in (sys.argv[1:] or PALETTES):
        open(f"kachat-chess-{variant}.svg", "w").write(svg(variant))
