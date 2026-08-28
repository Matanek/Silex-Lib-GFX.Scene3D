# GFX.Scene3D

`GFX.Scene3D` owns 3D scene data, its geometry, and the tools that genuinely
act on this domain: materials, lights, shadows, selection, and transform
gizmos. None of these concepts belongs to `GFX.Rendering` or a supposed
`Editor3D` domain.

```silex
use GFX.Scene3D.Material as Material3D
use GFX.Scene3D.Rotator as Rotator3D
use GFX.Scene3D.Transform as Transform3D
```

Mesh, grid, sprite, lighting, shadow, selection, and outline shaders live under
`Shaders/`. An alternative renderer can consume the public components,
use these assets as references, or provide its own shaders through `GFX.GPU`.
`Selection` and `TransformGizmo` remain explicit subdomains of `Scene3D`.

When a scene contains no ambient, sun, point, spot, cube-projector, or
tube-projector light component, the renderer supplies a camera-relative studio
rig with neutral ambient, key, fill, and rim illumination. Adding any explicit
light component disables this viewport fallback.

## Viewport axis

`ViewportAxis` displays the six world-axis directions relative to the active
3D camera. Positive X, Y, and Z directions use filled labeled markers; their
opposites use outlined markers. The overlay is presented in the top-right
logical viewport through the existing Canvas and Scene2D capabilities.

`ViewportAxisController` is deliberately separate. It tracks marker hover,
maps a left click to the corresponding front, back, left, right, top, or bottom
orientation while preserving the perspective projection and orbit distance,
and orbits the camera when the pointer drags the circular background. When the
application has no `ViewportCamera` resource, it leaves the display active and
performs no camera action.

```silex
application
    ..add_plugin(Scene3D.ViewportCamera())
    ..add_plugin(Scene3D.ViewportAxis())
    ..add_plugin(Scene3D.ViewportAxisController())
```

The flattened plugin catalog keeps dimensional names where 2D and 3D concepts
can meet:

```silex
application
    ..add_plugin(Plugins.ViewportCamera3D())
    ..add_plugin(Plugins.ViewportAxis3D())
    ..add_plugin(Plugins.ViewportAxisController3D())
```

`ViewportAxis.Settings` configures its top-right margin, square size, render
layer, resting and hovered circular backgrounds, and X/Y/Z colors.
`ViewportAxisController.Settings.button` selects the pointer button used for
preset views and circular-background orbit.

`Scene3D.Plugin` installs the ECS and generic rendering dependencies, owns the
built-in mesh cache, and registers a depth-aware Scene3D pass. Applications
remain free to omit it and consume `World`, `Meshes`, camera, material, and
light values from an alternative renderer.

```silex
application.add_plugin(Scene3D.Plugin())
```

## PBR materials

`Material` describes scalar surface properties. Optional image maps and raster
state live in the `MaterialSettings` ECS component; `MaterialTextures` groups
its texture inputs without becoming another component:

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

The forward renderer supports base-color, normal, metallic-roughness,
occlusion, and emission textures. Alpha masks discard below `alpha_cutoff`;
blended surfaces render after opaque surfaces, from far to near, without depth
writes. Texture transforms carry offset, scale, and rotation. The default
sampler repeats, filters linearly, generates mipmaps, and uses anisotropic
filtering.

## Imported models

`GFX.Assets.Model` remains a portable decoded value. `Scene3D.instantiate` is the
explicit bridge that converts its geometries and transforms, registers its
images, and spawns the corresponding mesh and material entities:

```silex
use GFX.Assets.GLTF
use GFX.Scene3D

let model = GLTF.load("Assets/Models/Robot.glb")
let instance = Scene3D.instantiate(model, world, meshes, images)
print("$(instance.entities.count()) primitives")
```

`ModelInstance` contains the spawned entities and roots. Procedural geometry
remains independent from imported assets: `Geometry.Cube.make()`,
`Geometry.Plane.make()`, and future generators continue to produce native
`Scene3D.Geometry.Mesh` values for `Meshes.add`.

## Camera-fitted sun shadows

A `SunLight` whose `shadow_follows_camera` value is enabled distributes its
shadow atlas space across four stabilized cascades fitted to the active camera
frustum. Each cascade uses the tight light-space bounds of its eight frustum
corners instead of enclosing their diagonal in a square bounding sphere. The
split distribution favors the first meters around the camera and progressively
reduces precision toward `shadow_distance`. This keeps nearby contact shadows
sharp without wasting texels on unseen space. Setting
`shadow_follows_camera` to `false` preserves the fixed orthographic projection
defined by `shadow_center`, `shadow_size`, and `shadow_depth`.

`shadow_distance` is the intended world-space quality boundary for a moving
camera. A zero value retains the legacy range derived from `shadow_size` and
`shadow_depth`; an explicit positive value is preferable for world scenes.

By default, the renderer derives the four cascade endings automatically.
`shadow_cascade_distances` can instead provide four strictly increasing world
distances whose last value does not exceed `shadow_distance`. A zero or invalid
vector keeps the automatic distribution. This is useful when small details are
limited to the first cascade but must retain their shadows farther from the
camera:

```silex
var sun = Scene3D.SunLight()
sun.shadow_distance = 45.0
sun.shadow_cascade_distances = Math.Vec4(22.0, 31.0, 38.0, 45.0)
```

The renderer selects a sampled D32 shadow format when available, then falls
back to D24 or D16. Shadow casters use slope-aware raster depth bias and
back-face culling to prevent self-shadowing patterns before filtering. Four sun
cascades occupy an 8192 atlas, preserving 4096x4096 effective texels per
cascade. This matches the spatial shadow resolution used by the historical
WorldDemo instead of enlarging a 2048-tile edge with filtering.

Sun shadows use percentage-closer soft shadows through
`Shadow.sun().softness`: eight depth taps estimate the nearest blockers, then a
16-tap Poisson PCF adapts the penumbra to their separation from the receiver.
Comparison taps retain GPU bilinear depth filtering. Setting
`sun.shadow.softness` to zero selects one bilinear comparison.

Adjacent sun cascades overlap by eight percent and blend across that shared
range. Resolution and bias therefore change progressively instead of producing
a hard line at a cascade boundary.

## Automatic batching

The built-in renderer automatically instances compatible opaque and alpha-mask
entities that share their mesh, material values, textures, and raster state.
The same persistent instance buffers feed the forward and shadow passes. Static
matrix contents stay on the GPU until their transforms change. Batches with a
finite shadow distance are divided into persistent spatial chunks. Those chunks
are rejected against the camera frustum before the forward draw, then against
both each cascade frustum and the configured detail distance before a sun-shadow
draw. Blended entities remain individual draws so their far-to-near ordering
stays correct.

Small repeated details can restrict how far and through how many sun cascades
they cast shadows. A zero `shadow_distance` keeps the unbounded default;
`shadow_cascades` accepts one through four. The renderer derives and culls its
spatial chunks internally:

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

`casts_shadows:false` removes an object from every shadow pass without hiding
it from the color pass.

Normal ECS usage does not require a batching component: applications can keep
spawning `Transform`, `Mesh`, `Material`, and optional `MaterialSettings`
components. For thousands of static repetitions, `Instances` stores every
local transform on one entity and avoids scanning thousands of equivalent ECS
entities each frame. Changing the collection through `replace`, `append`, or
`clear` increments its revision and refreshes its GPU buffers.

`Rendering.Stats` exposes color and shadow draw, instance, and triangle work
separately, in addition to their totals and the pipeline, pass, uniform, and
texture work.

## Procedural scatter

`Scatter` deterministically generates ordinary `Transform` values from a seed.
Its horizontal spawn area can be a box or a circle; additional areas can be
excluded. Position, Euler rotation, uniform or per-axis scale, soft edges, and
center-to-edge scale variation can be configured independently:

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

Scatter stays independent from assets and ECS recipes: the same placements can
instantiate a mesh, several entities forming one object, an `Instances`
component for a dense static field, or another consumer's components.
Compatible generated entities are picked up by automatic batching. A seed
always reproduces the same placements and variations. An impossible exclusion
can yield fewer transforms than requested after bounded placement attempts.

## Tone mapping

Tone mapping is part of the Scene3D mesh shading contract rather than a
generic rendering concern. `Shaders/Mesh.hlsl` contains the Reinhard,
ACES, Khronos PBR Neutral, Filmic, and AgX operators. Filmic and AgX use the
RGBA16F lookup tables under `Assets/ToneMapping/`.

```silex
use GFX.Scene3D.ToneMapping as ToneMapping3D
use GFX.Scene3D.ToneMapping.Tables

let settings = ToneMapping3D.agx(exposure:0.5)
let tables = Tables.bundled()
```

`Tables` is public so an alternative renderer can reuse the same validated
transforms instead of depending on a private shader payload. The generation
script lives at `Tools/GenerateToneMappingLUTs.py`.
