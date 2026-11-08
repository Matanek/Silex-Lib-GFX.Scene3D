# Historique

## [0.4.0] - 2026-11-08

- Recalcule les bornes de visibilité des lots quand le rayon du maillage change, même à transformation inchangée ; les géométries déformables restent visibles pendant leur déplacement.

- `Geometry.Cylinder.make` crée un cylindre fermé configurable : normales radiales, bouchons séparés, couture UV et validation des dimensions/résolution.

- Adopte la déclaration `Result` unique : l’appel ordinaire rend la valeur
  ou arrête le programme sur erreur ; `try appel()` conserve le `Result`. Les
  anciens appels stockant un résultat et propagations deviennent explicites.
  Cette version requiert Silex 0.48.0 ou supérieur et les versions coordonnées
  de ses dépendances.

- Conserver les clips Canvas dans `CanvasPanel` et refuser explicitement leur conversion en meshes avec `Meshes.add_canvas_geometry`.

- Les meshes vectoriels issus de lignes Canvas avec police de secours conservent des caches de contours distincts par face.

- `ViewportAxisController3D` installe automatiquement son widget et sa caméra, avec leurs dépendances graphiques. Les réglages explicites et une caméra première personne déjà demandée sont conservés.
