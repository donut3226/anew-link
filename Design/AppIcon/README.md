# App icon

**Chosen (9 Nov 2026): concept 7 "Sunrise clasp"** for the normal icon, and **concept 9 "Night clasp"** for the dark home-screen style. Both are original artwork, no Sony or Wena marks. Explored on the Claude Design canvas "Anew Link icon".

- `concepts/`: all nine concept SVGs (1024 x 1024). 7 and 9 are the sources of the app icon.
- The app's icon set is `MyApp/Assets.xcassets/AppIcon.appiconset`: `AppIcon.png` (7), `AppIcon-Dark.png` (9), `AppIcon-Tinted.png` (9 in grey, which iOS colours in Tinted mode). The PNGs were rendered from the SVGs with Quick Look (WebKit) and flattened to 1024 x 1024 with no transparency, as Apple requires.
- In-app choice (`MyApp/AppIconPicker.swift`): Automatic (the main set above), Sunrise always (`AppIcon-Sunrise.appiconset`) or Night always (`AppIcon-Night.appiconset`), registered in `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`.
- To change the icon: edit the SVG, render it again, and replace the PNGs.

## Earlier attempt: "renew buckle" (not used)


A strap through a buckle whose frame is drawn as a loop arrow: the band's buckle, given a new life ("Anew"). Original artwork, no Sony or Wena marks.

- `layers/`: the artwork as separate SVG layers for Icon Composer, 1024 x 1024, all white (colours are set in Icon Composer).
  - `1-strap.svg`: the strap (back)
  - `2-buckle.svg`: the buckle frame with its arrow
  - `3-prong.svg`: the prong (front)
- `preview-light.svg`, `preview-dark.svg` and their `.png` renders: how it should roughly look. Icon Composer adds the real Liquid Glass depth.

## Colours

| | Light | Dark |
|---|---|---|
| Background, top | `#23A39A` | `#16302F` |
| Background, bottom | `#0B2540` | `#05090C` |
| Strap | white, about 25% opacity | white, about 14% opacity |
| Buckle and prong | white | mint `#7FE3D6` |

## Making the icon in Icon Composer

1. In Xcode: **Xcode > Open Developer Tool > Icon Composer**, then **File > New**.
2. Drag the three files from `layers/` onto the canvas. Put the strap in its own group, and the buckle and prong together in a second group above it. Separate groups are what give the glass its depth.
3. Select the background (the canvas itself) and set its fill to a gradient using the light colours above.
4. Select the strap layer: fill white, opacity about 25%.
5. Select the buckle group: leave Liquid Glass on and try the shadow and highlight settings until it looks right.
6. Switch the preview to **Dark** and set the dark colours, then check **Tinted** (it's automatic, just make sure it reads well).
7. **File > Save** as `AppIcon.icon` in this folder (`Design/AppIcon/`), then tell Claude, who adds it to the app.
