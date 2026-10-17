# Handoff: Intellego app icon (concept 2c, "Stressed vowel")

## About these files
The SVGs are a vector master built from the HTML design reference (`Intellego Icon.dc.html`, concept **2c**). Open the HTML design in a browser to compare. Produce platform assets from the SVG master; don't ship the HTML.

**Before generating PNGs:** the letter "а" is live text set in **Spectral SemiBold (600)** (Google Fonts, OFL). Install the font, then convert the text to outlines so rendering doesn't depend on fonts:
`inkscape intellego-icon-fullbleed.svg --export-text-to-path --export-plain-svg -o icon.svg`
Check glyph and stress-mark placement against the HTML; the mark should sit just above-right of the "а" bowl, like an acute accent.

## Design
240×240 artboard (scale freely):
- Background: coral `#E57255` (oklch 0.68 0.15 35), full bleed
- Speech bubble: `#FBF8F1`, rect x38 y39 w164 h148, corner radius 40
- Tail: same fill, attached at bottom-right. It starts wide (x124–180 at y179), tapers, and curves to a point at (188,227)
- Glyph: Cyrillic "а" (U+0430), Spectral 600, 124 units, `#1D2433`, centred at x120, baseline ≈ y139
- Stress mark: rounded bar 13×36 (rx 6.5), teal `#00866E` (oklch 0.55 0.11 175), rotated 38°, centred at (128.5, 64)
- Monochrome/themed: bubble solid, glyph knocked out, stress mark dropped (it's too small to survive one-tone tinting); see `intellego-icon-monochrome.svg`

## Files
- `intellego-icon-fullbleed.svg`: square master (Android legacy, Windows, Linux, favicon)
- `intellego-icon-squircle.svg`: macOS/iOS-style rounded (radius 22.5%)
- `intellego-icon-foreground.svg`: transparent foreground for the Android adaptive layer
- `intellego-icon-monochrome.svg`: Android 13+ themed icon layer
- `Intellego Icon.dc.html`: design reference

## Platform targets
- **Android adaptive** (`mipmap-anydpi-v26/ic_launcher.xml`): background is a colour `#E57255`; foreground is `intellego-icon-foreground.svg` converted to a VectorDrawable (Android Studio › Image Asset), scaled so the bubble stays inside the 66dp safe zone of the 108dp canvas (about 72% of current size, centred); monochrome uses the monochrome SVG.
- **Linux** (freedesktop hicolor): `share/icons/hicolor/scalable/apps/intellego.svg` (outlined fullbleed or squircle), plus PNGs at 16, 24, 32, 48, 64, 128, 256 and 512 in `hicolor/NxN/apps/`; reference `Icon=intellego` in the .desktop file.
- **Windows**: .ico with 16, 24, 32, 48 and 256: `magick icon.svg -define icon:auto-resize=256,48,32,24,16 intellego.ico`
- **macOS**: .icns from the squircle SVG at 16–1024 (`iconutil` from an .iconset).
- **Web/WASM**: favicon.svg (fullbleed), plus apple-touch-icon 180, and PWA manifest icons at 192 and 512 (maskable = fullbleed with the bubble inside the central 80%).
- PNG export: `rsvg-convert -w N -h N icon.svg -o icon-N.png`

If the project uses a cross-platform framework (Tauri, Flutter, etc.), feed a 1024px PNG of the fullbleed master to its icon generator (`tauri icon`, `flutter_launcher_icons`).
