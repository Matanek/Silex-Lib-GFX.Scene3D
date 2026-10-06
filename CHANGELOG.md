# Changelog

## [Unreleased]

- Preserve Canvas clips in `CanvasPanel` and explicitly reject mesh conversion through `Meshes.add_canvas_geometry`.

- Vector meshes built from Canvas lines using a fallback font retain separate outline caches per face.

- `ViewportAxisController3D` automatically installs its widget and camera with their graphical dependencies. Explicit settings and an explicitly requested first-person camera are preserved.
