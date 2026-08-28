# GFX.Scene3D

`GFX.Scene3D` possède les données de scène 3D et les outils qui agissent
réellement sur ce domaine : matériaux, lumières, ombres, sélection et gizmos de
transform. Ces concepts n’appartiennent ni à `GFX.Rendering`, ni à un domaine
éditeur séparé.

```silex
use GFX.Scene3D.Material as Material3D
use GFX.Scene3D.Rotator as Rotator3D
use GFX.Scene3D.Transform as Transform3D
```

Les shaders de maillage, grille, sprite, lumière, ombre, sélection et outline
appartiennent au package. Sans lumière explicite, le renderer fournit un
éclairage studio neutre relatif à la caméra. Ajouter une lumière désactive ce
repli.

## Axe de viewport

`ViewportAxis` affiche les six directions du monde dans le coin supérieur
droit. Son controller séparé gère survol, vues prédéfinies et orbite.

```silex
application
    ..add_plugin(Scene3D.ViewportCamera())
    ..add_plugin(Scene3D.ViewportAxis())
    ..add_plugin(Scene3D.ViewportAxisController())
```

Le catalogue aplati conserve les suffixes dimensionnels :

```silex
application
    ..add_plugin(Plugins.ViewportCamera3D())
    ..add_plugin(Plugins.ViewportAxis3D())
    ..add_plugin(Plugins.ViewportAxisController3D())
```

`Scene3D.Plugin` installe ECS et Rendering, possède le cache de meshes et
enregistre une passe 3D avec profondeur. Un renderer alternatif peut consommer
les mêmes composants sans ce plugin.

```silex
application.add_plugin(Scene3D.Plugin())
```

## Matériaux PBR

`Material` décrit les propriétés scalaires. `MaterialSettings` porte textures
et état raster, et `MaterialTextures` regroupe les images sans devenir un
composant supplémentaire.

```silex
use GFX.Assets.Image
use GFX.Color
use GFX.ECS
use GFX.Scene3D

let albedo = images.add(Image.solid(Color.white()))
world.spawn(ECS.EntityRecipe()
    ..with(Scene3D.Transform())
    ..with(Scene3D.Mesh(mesh))
    ..with(Scene3D.Material(
        metallic:0.2,
        roughness:0.6
    ))
    ..with(Scene3D.MaterialSettings(
        textures:Scene3D.MaterialTextures(
            albedo:Scene3D.MaterialTexture(image:albedo)
        ),
        alpha:Scene3D.AlphaMode.blend,
        double_sided:true
    ))
)
```

Le renderer gère textures de couleur, normale, metallic-roughness, occlusion et
émission. Les surfaces blend sont triées loin-vers-près sans écriture de
profondeur. Le sampler par défaut répète, filtre linéairement, génère les
mipmaps et utilise l’anisotropie.

## Modèles importés

`GFX.Assets.Model` reste une valeur décodée portable. `Scene3D.instantiate` est
le pont explicite vers les meshes, images et entités de scène.

```silex
use GFX.Assets.GLTF
use GFX.Scene3D

let model = GLTF.load("Assets/Models/Robot.glb")
let instance = Scene3D.instantiate(model, world, meshes, images)
print("$(instance.entities.count()) primitives")
```

La géométrie procédurale reste indépendante et produit des
`Scene3D.Geometry.Mesh` natifs.

## Ombres solaires ajustées à la caméra

Un `SunLight` avec `shadow_follows_camera` répartit l’atlas sur quatre cascades
stabilisées ajustées au frustum. `shadow_distance` fixe la frontière de qualité.
Des distances strictement croissantes peuvent remplacer la distribution
automatique.

```silex
var sun = Scene3D.SunLight()
sun.shadow_distance = 45.0
sun.shadow_cascade_distances = Math.Vec4(22.0, 31.0, 38.0, 45.0)
```

Le renderer choisit D32, puis D24 ou D16. Les ombres utilisent biais de
profondeur, back-face culling, PCSS et transition chevauchée entre cascades.
Une douceur nulle sélectionne une comparaison bilinéaire unique.

## Batching automatique

Les entités opaques et alpha-mask compatibles sont automatiquement instanciées.
Les buffers persistants servent aux passes forward et shadow. Les chunks sont
rejetés contre frustums et distance de détail ; les surfaces blend restent des
draws séparés pour conserver leur ordre.

```silex
world.spawn(ECS.EntityRecipe()
    ..with(Scene3D.Transform())
    ..with(Scene3D.Instances(grass_transforms))
    ..with(Scene3D.Mesh(
        grass_mesh,
        shadow_distance:20.0,
        shadow_cascades:1
    ))
    ..with(grass_material)
)
```

`Instances` évite des milliers d’entités ECS équivalentes et rafraîchit ses
buffers quand `replace`, `append` ou `clear` change sa révision.

## Dispersion procédurale

`Scatter` produit des `Transform` déterministes à partir d’une seed, dans une
boîte ou un cercle, avec exclusions et variations de position, rotation et
échelle.

```silex
var rocks = Scene3D.Scatter(
    count:200,
    area:Scene3D.ScatterArea.box(Math.Vec2(80.0)),
    seed:42
)
rocks.exclude(Scene3D.ScatterArea.circle(5.0))
rocks.vary_rotation(Math.Vec3(), Math.Vec3(0.2, Math.two_pi(), 0.2))
rocks.vary_scale(Math.Vec3(0.3), Math.Vec3(1.8))
rocks.soften_edges(0.2)

for transform in rocks.generate() {
    world.spawn(ECS.EntityRecipe()
        ..with(transform)
        ..with(Scene3D.Mesh(rock_mesh))
        ..with(rock_material)
    )
}
```

Une exclusion impossible peut produire moins de transforms après un nombre
borné d’essais. Les placements restent indépendants d’ECS et des assets.

## Tone mapping

Le tone mapping appartient au shading de Scene3D. Le shader fournit Reinhard,
ACES, Khronos PBR Neutral, Filmic et AgX ; Filmic et AgX utilisent les LUT
RGBA16F distribuées.

```silex
use GFX.Scene3D.ToneMapping as ToneMapping3D
use GFX.Scene3D.ToneMapping.Tables

let settings = ToneMapping3D.agx(exposure:0.5)
let tables = Tables.bundled()
```

`Tables` est public afin qu’un renderer alternatif réutilise les transforms
validés sans dépendre d’un payload shader privé.
