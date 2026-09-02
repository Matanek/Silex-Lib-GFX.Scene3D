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

`Silex-Examples/Sources/CanvasProjection3D.sx` distingue une ombre graphique
Canvas 2D d’un `CanvasPanel` éclairé qui projette une vraie ombre 3D selon son
alpha.
