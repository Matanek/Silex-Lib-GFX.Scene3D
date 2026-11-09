# Changelog

## [0.4.0] - 2026-11-09

- Refresh batch visibility bounds when the mesh radius changes, even with unchanged transforms, keeping deforming world-space geometry visible as it travels.

- `Geometry.Cylinder.make` creates a configurable closed cylinder with radial normals, separate caps, a UV seam and dimension/resolution validation.

- Adopts one `Result` declaration: an ordinary call returns the value or
  stops the program on failure; `try call()` keeps the `Result`. Existing calls
  storing results and propagating failures are made explicit. This version
  requires Silex 0.48.0 or newer and the coordinated dependency versions.

- Preserve Canvas clips in `CanvasPanel` and explicitly reject mesh conversion through `Meshes.add_canvas_geometry`.

- Vector meshes built from Canvas lines using a fallback font retain separate outline caches per face.

- `ViewportAxisController3D` automatically installs its widget and camera with their graphical dependencies. Explicit settings and an explicitly requested first-person camera are preserved.
