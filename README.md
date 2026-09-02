# GFX.Scene3D

`GFX.Scene3D` fournit des scènes 3D retenues avec géométrie, matériaux PBR,
éclairage, caméras, ombres et rendu GPU.

```text
silex install GFX.Scene3D
```

## Documentation

- [Documentation française](Docs/FR/README.md)
- [English documentation](Docs/EN/README.md)

Le package nécessite Silex 0.43.0 ou une version ultérieure.

Le démonstrateur public `Silex-Examples/Sources/VectorFontShowcase/Main.sx`
montre un `GlyphRun` converti en géométrie planaire éclairée, avec matériau PBR
et ombre projetée sur un receiver distinct.

`Silex-Examples/Sources/CanvasProjection3D.sx` convertit des formes
`GFX.Canvas` et du texte `GFX.Font` en triangles planaires avec
`Meshes.add_canvas_geometry`. La géométrie reste indépendante de la résolution,
reçoit un matériau PBR et projette sa silhouette — contours de glyphes compris —
sur un receiver distinct. L’exemple n’emploie ni `CanvasPanel` ni texture
intermédiaire.
