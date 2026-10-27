# KaChat Chess app icon

A chess king in KaChat teal with the Kaspa mark (the backward K) cut into its body, standing on
a strip of board. The backward K is the same drawing as KaPosts' and KaChat Wallet's icons.
`python3 make_chess_icon.py` writes `kachat-chess-light.svg`, `kachat-chess-dark.svg` and
`kachat-chess-tinted.svg`. Render each at 1024x1024 and save it opaque (no alpha) into
`KaChatChess/Resources/Assets.xcassets/AppIcon.appiconset` (`white.png`, `dark.png`,
`Icon-iOS-TintedDark-1024x1024@1x.png`). On a Mac without other tools:

```bash
python3 make_chess_icon.py && qlmanage -t -s 1024 -o . kachat-chess-light.svg
sips -s format jpeg kachat-chess-light.svg.png --out t.jpg && sips -s format png t.jpg --out white.png
```

`KaChatChessLogo.imageset` (the sign-in screen's logo, next to "KaChat Chess") is the light icon
at 512 px.
