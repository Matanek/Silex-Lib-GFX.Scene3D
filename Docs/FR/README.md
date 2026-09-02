# GFX.Scene3D

`GFX.Scene3D` possède les données de scène 3D et les outils qui agissent
réellement sur ce domaine : matériaux, lumières, ombres, sélection et gizmos de
transform. Ces concepts n’appartiennent ni à `GFX.Rendering`, ni à un domaine
éditeur séparé.

Le démonstrateur exécutable
`Silex-Examples/Sources/VectorFontShowcase/Main.sx` fournit les quatre petites
fonctions `required_*` qui rendent la politique d’erreur de l’application
explicite ; le cœur de son usage est :

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

Le catalogue aplati conserve les suffixes dimensionnels :

```silex
use GFX.Plugins

application
    ..add_plugin(Plugins.ViewportCamera3D())
    ..add_plugin(Plugins.ViewportAxis3D())
    ..add_plugin(Plugins.ViewportAxisController3D())
```

`Plugins.Scene3D` installe ECS et Rendering, possède le cache de meshes et
enregistre une passe 3D avec profondeur. Un renderer alternatif peut consommer
les mêmes composants sans ce plugin.

```silex
application.add_plugin(Plugins.Scene3D())
```

Avec `Plugins.BundleManager`, ce Plugin peut rester global afin que les
catalogues, pipelines et lots survivent aux transitions. Il étend
automatiquement les Bundles avec le même `Plugins.Scene3D` ; les systèmes de
préparation consultent alors leur `World` local. `Plugins.Scene2D` suit la même
règle et les deux domaines peuvent préparer le contenu d’un même Bundle.

```silex
application
    ..add_plugin(Plugins.Scene2D())
    ..add_plugin(Plugins.Scene3D())
    ..add_plugin(Plugins.BundleManager(bundle))
```

Un Bundle autonome peut installer `Plugins.Scene3D()` lui-même afin de posséder
sa fenêtre et sa pile de rendu.

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

## Texte vectoriel planaire

`Scene3D.Text` convertit un `GFX.Font.GlyphRun` façonné en triangles physiques.
Le plan fournit une origine et deux axes 3D non nuls et non colinéaires. L’axe
Y-up de la fonte est conservé, la normale est le produit vectoriel normalisé
des axes, et le mesh obtenu emprunte ensuite exactement le chemin ordinaire de
`Mesh`, `Material`, des lumières et des shadow maps.

```silex
use GFX.Font
use GFX.Scene3D
use STD.Math

var face = required_face(Font.Face.default())
var instance = required_instance(Font.Instance.create(face, size:1.0))
var run = required_run(instance.shape("Silex"))
let source = Scene3D.Text(
    run,
    plane:Scene3D.TextPlane(
        origin:Math.Vec3(0.0, 1.0, 0.0),
        x_axis:Math.Vec3(0.01, 0.0, 0.0),
        y_axis:Math.Vec3(0.0, 0.01, 0.0)
    )
)
let handle = required_text(meshes.add_text(source))
world.spawn(ECS.EntityRecipe()
    ..with(Scene3D.Transform())
    ..with(Scene3D.Mesh(handle, casts_shadows:true))
    ..with(Scene3D.Material(roughness:0.7))
    ..with(Scene3D.MaterialSettings(double_sided:true))
)
```

`Meshes` possède un cache borné de 1 024 tessellations, indexé par face,
variations, synthèse, glyphe et tolérance, mais pas par taille, couleur,
placement, caméra ou lumière. Deux textes de tailles différentes partagent
donc les mêmes triangles normalisés. `text_cache_stats()` rend les hits,
tessellations et placements observables pour les tests et profils.

`add_canvas_text` accepte aussi un `Canvas.TextLayer` vector-compatible et
applique explicitement son repère Y-down. Un glyphe bitmap/couleur sans contour
échoue avant la frame avec un `TextError` indiquant la face, le glyphe et son
cluster. `text_bounds(handle)` retourne les bornes physiques du mesh.

Le texte reste une surface sans épaisseur : `double_sided` est recommandé
quand il doit être visible des deux côtés. `casts_shadows:false` le retire de la
passe d’ombre. Les modes `opaque` et `mask` existants fonctionnent sans texture
alpha, puisque la silhouette et ses trous sont déjà décrits par les triangles.
Extrusion, bevel et parois latérales ne font pas partie de cette version.

## Panneaux Canvas et géométrie planaire

`CanvasPanel` conserve un Canvas sur une surface rectangulaire Scene3D. Le
frame logique, la densité fixe et la taille monde sont indépendants ; la
texture mesure exactement `ceil(frame * density)`. Le service public
`CanvasPanels` expose séparément mises à jour de surface, hits de cache et
passes d’ombre. Déplacer le panneau ou une lumière ne rerastérise pas le
Canvas ; modifier le dessin ne rafraîchit que sa surface.

```silex
world.spawn(ECS.EntityRecipe()
    ..with(Scene3D.Transform(position:Math.Vec3(0.0, 1.0, 0.0)))
    ..with(Scene3D.CanvasPanel(
        drawing,
        Canvas.Rect(Math.Vec2(), Math.Vec2(320.0, 180.0)),
        1.5,
        Math.Vec2(3.2, 1.8)
    ))
    ..with(Scene3D.CanvasPanelMaterial(
        alpha:Scene3D.AlphaMode.mask,
        alpha_cutoff:0.2
    ))
)
```

Le matériau dédié échantillonne la surface linéaire prémultipliée, la remet en
alpha droit pour l’éclairage, puis prémultiplie la sortie blend. Les modes
`opaque`, `mask`, `blend` et `unlit` sont explicites. Une ombre alpha-mask
échantillonne la couverture du Canvas ; elle ne projette pas le rectangle
plein. Une surface blend conserve les limites de tri des transparences 3D.

`Meshes.add_canvas_geometry` exprime l’autre intention. Il convertit les formes
vectorielles, gradients linéaires et textes à contours vers des positions,
normales et UV physiques selon un `PlaneMapping`. Les cercles et rectangles
arrondis sont réellement tessellés, donc leurs ombres respectent la
silhouette. ImagePaint, effets raster, frame dégénéré et axes colinéaires sont
refusés explicitement ; utiliser `CanvasPanel` pour ces cas. La conversion ne
crée ni extrusion ni bevel.

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
