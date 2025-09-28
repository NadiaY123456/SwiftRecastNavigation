# SplatMeshGenerator Parameter Reference

### `maxEdgeLength: CGFloat`
- **What it is**  
  The maximum allowed length (in image-space points) for any edge in your output mesh after resampling.
- **Practical impact**  
  - **Lower values** → more, shorter edges → denser mesh, higher fidelity, but slower to compute and heavier in memory.  
  - **Higher values** → fewer, longer edges → coarser mesh with less detail, faster and lighter.
- **When to change**  
  - If your mesh looks blocky or angular on curves, **decrease** it.  
  - If performance or triangle-count is a problem and you can tolerate rougher shapes, **increase** it.
- **Tips**  
  - Base it on the smallest feature you care about: e.g. if you need to capture details down to ~5 px in size, set `maxEdgeLength` ≤ 5.  
  - Match it to your rendering scale: higher-DPI outputs may need smaller values.

### `simplificationTolerance: CGFloat`
- **What it is**  
  The Douglas–Peucker simplification tolerance, expressed as a fraction of the shorter side of the source image. Internally, the code multiplies this by `min(width, height)` to get an absolute tolerance in points.
- **Practical impact**  
  - **Lower values** → very little simplification → more original contour points preserved → more complex boundary, more triangles.  
  - **Higher values** → aggressive simplification → smoother, straighter boundaries, fewer vertices.
- **When to change**  
  - If your shapes have a lot of tiny wiggles or noise, and you want to smooth them, **increase** it.  
  - If you’re losing important detail (e.g. sharp corners), **decrease** it.
- **Tips**  
  - Start around `0.005` (0.5% of the image short side) and adjust up or down by factors of two.  
  - Watch for “missing” small protrusions: that’s a sign your tolerance is too high.

### `threshold: Float?`
- **What it is**  
  The cutoff in [0…1] for binarizing the chosen channel. If `nil`, the code tries to compute an Otsu threshold automatically, falling back to 0.5 if that fails.
- **Practical impact**  
  - **Lower threshold** → more of the darker pixels become “foreground” (white in the mask).  
  - **Higher threshold** → only the brightest pixels become foreground.
- **When to change**  
  - If your shapes are poorly separated by brightness (e.g. uneven illumination), auto-Otsu may fail—try manually setting it.  
  - For consistently lit, high-contrast images, auto (leave `nil`) usually suffices.
- **Tips**  
  - Visualize the mask: if too much background leaks in, raise the threshold; if your object is disappearing, lower it.  
  - Otsu can be biased by extreme outliers; manual tuning is sometimes necessary for very dark or very bright scenes.

### `channel: Channel`
- **What it is**  
  Which color channel to extract before thresholding: `.red`, `.green`, `.blue`, `.alpha`, or `.grayscale` (luma).
- **Practical impact**  
  Different channels may offer better contrast for different objects (e.g. red flowers against green leaves).
- **When to change**  
  - If your object is a particular color that stands out in one channel (e.g. bright red), pick that channel.  
  - If you have an alpha mask already in the image (PNG with transparency), use `.alpha`.  
  - Otherwise, `.grayscale` is a reasonable default.
- **Tips**  
  - Try each channel in debug mode to see which yields the cleanest binary mask.  
  - RGB channels are identical for grayscale images—no harm in leaving it default.

### `invertMask: Bool?`
- **What it is**  
  Whether to invert the binary mask after thresholding:  
  - `nil` → **auto** (currently just means “don’t invert” by default)  
  - `false` → don’t invert (detect bright shapes)  
  - `true` → invert (detect dark shapes)
- **Practical impact**  
  If your shapes are darker than the background, you’ll need to invert so they become the “foreground.”
- **When to change**  
  - If you see the mesh hugging the background region instead of the object, set `invertMask = true`.  
  - For bright-on-dark subjects, leave it `false` (or `nil`).
- **Tips**  
  - In auto (`nil`) mode the code currently assumes “no invert”—override explicitly if you need dark-shape detection.  
  - Pair with manual `threshold` if Otsu + invert still misses your silhouette.

### `morphologyRadius: Int`
- **What it is**  
  The radius (in pixels) for a “closing” operation: a dilation followed by an erosion. Use 0 to skip this step.
- **Practical impact**  
  - **Small radius** (1–3) → removes tiny holes and connects very close contours.  
  - **Large radius** → aggressively smooths and can merge nearby shapes or overly round corners.
- **When to change**  
  - If your mask has speckles or tiny gaps, **increase** to fill them.  
  - If shapes merge or lose detail, **decrease** or disable (set to 0).
- **Tips**  
  - Use sparingly—morphology can dramatically change topology if over-applied.  
  - Inspect with debug on to see how the mask evolves after each step.

### `interiorSpacingFactor: CGFloat`
- **What it is**  
  A multiplier on `maxEdgeLength` that determines the spacing of interior sample points (used to seed the triangulation).
- **Practical impact**  
  - **Lower factor** (e.g. 0.5) → more interior points → better‐shaped triangles inside large polygons, but more triangles overall.  
  - **Higher factor** (e.g. 0.9) → fewer interior points → coarser interior triangulation, fewer triangles.
- **When to change**  
  - If you see long, skinny triangles in the interior of your mesh, **decrease** the factor to add more points.  
  - If performance is an issue and interior quality is okay, **increase** toward 1.0.
- **Tips**  
  - The default of 0.8 strikes a balance; tweak by ±0.1 to dial in interior quality vs. triangle-count.

### `debugPrint: Bool`
- **What it is**  
  Toggles verbose console logging of each pipeline stage (threshold values, contour counts, fallback warnings, etc.).
- **Practical impact**  
  - **Enabled** → lots of diagnostic output, invaluable for tuning parameters.  
  - **Disabled** → quieter, slightly faster, cleaner logs.
- **When to change**  
  - Turn **on** when you’re trying to understand why a particular shape isn’t being detected correctly.  
  - Turn **off** for production or when you no longer need step-by-step insight.
- **Tips**  
  - Even a quick run with `debugPrint = true` can reveal if Otsu is failing or if your morphology radius is too large.
