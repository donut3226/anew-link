# App icon: "renew buckle"

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
