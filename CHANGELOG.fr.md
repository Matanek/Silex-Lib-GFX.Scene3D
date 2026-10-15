# Historique

## [Unreleased]

- `Geometry.Cylinder.make` crée un cylindre fermé configurable : normales radiales, bouchons séparés, couture UV et validation des dimensions/résolution.

- Adopte la déclaration `Result` unique : l’appel ordinaire rend la valeur
  ou arrête le programme sur erreur ; `try appel()` conserve le `Result`. Les
  anciens appels stockant un résultat et propagations deviennent explicites.
  Cette révision requiert la toolchain de développement avec cette sémantique
  de `try` ; sa publication doit coordonner les versions du compilateur et des
  packages.

- Conserver les clips Canvas dans `CanvasPanel` et refuser explicitement leur conversion en meshes avec `Meshes.add_canvas_geometry`.

- Les meshes vectoriels issus de lignes Canvas avec police de secours conservent des caches de contours distincts par face.

- `ViewportAxisController3D` installe automatiquement son widget et sa caméra, avec leurs dépendances graphiques. Les réglages explicites et une caméra première personne déjà demandée sont conservés.
