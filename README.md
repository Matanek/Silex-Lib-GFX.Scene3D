# GFX.Scene3D

`GFX.Scene3D` provides retained 3D scenes with geometry, PBR materials,
sprites and billboards, lighting, cameras, shadows, and GPU rendering.

```text
silex install GFX.Scene3D
```

## Documentation

- [French documentation](Docs/FR/README.md)
- [English documentation](Docs/EN/README.md)

The package requires Silex 0.43.0 or newer.

The public `Silex-Examples/Sources/VectorFontShowcase/Main.sx` demonstration
shows a `GlyphRun` converted into lit planar geometry, with a PBR material and
a shadow cast onto a separate receiver.

`Silex-Examples/Sources/CanvasProjection3D.sx` converts `GFX.Canvas` shapes and
`GFX.Font` text into planar triangles with `Meshes.add_canvas_geometry`. The
geometry remains resolution-independent, receives a PBR material, and casts
its silhouette—including glyph outlines—onto a separate receiver. The example
uses neither `CanvasPanel` nor an intermediate texture.

`Scene3D.Geometry.Cylinder.make` creates a closed, UV-mapped cylinder centered on local Y; see the [geometry consumer](Tests/Consumer/Tests/Cylinder.sx).
