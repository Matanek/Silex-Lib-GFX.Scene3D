# Historique

## [Unreleased]

- Conserver les clips Canvas dans `CanvasPanel` et refuser explicitement leur conversion en meshes avec `Meshes.add_canvas_geometry`.

- Les meshes vectoriels issus de lignes Canvas avec police de secours conservent des caches de contours distincts par face.

- `ViewportAxisController3D` installe automatiquement son widget et sa caméra, avec leurs dépendances graphiques. Les réglages explicites et une caméra première personne déjà demandée sont conservés.
