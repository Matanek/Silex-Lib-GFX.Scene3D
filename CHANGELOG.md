# Changelog

## [Unreleased]

- `Geometry.Cylinder.make` creates a configurable closed cylinder with radial normals, separate caps, a UV seam and dimension/resolution validation.

- Adopts one `Result` declaration: an ordinary call returns the value or
  stops the program on failure; `try call()` keeps the `Result`. Existing calls
  storing results and propagating failures are made explicit. This revision
  requires the development toolchain with these `try` semantics; publication
  must coordinate compiler and package versions.

- Preserve Canvas clips in `CanvasPanel` and explicitly reject mesh conversion through `Meshes.add_canvas_geometry`.

- Vector meshes built from Canvas lines using a fallback font retain separate outline caches per face.

- `ViewportAxisController3D` automatically installs its widget and camera with their graphical dependencies. Explicit settings and an explicitly requested first-person camera are preserved.
