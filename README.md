# GFX.Scene3D

`GFX.Scene3D` provides retained 3D scenes for GFX: procedural geometry,
imported-model instantiation, cameras, materials, lighting, shadows, selection,
gizmos, a Blender-style viewport axis, sprites, scatter, tone mapping, and the
built-in GPU renderer.

```text
silex install GFX.Scene3D
```

```silex
use GFX.Application
use GFX.Components
use GFX.ECS
use GFX.Plugins
use GFX.Resources
use GFX.Scene3D

func create_scene(world:&Resources.World, meshes:&Resources.Meshes3D) {
    let cube = meshes.add(Scene3D.Geometry.Cube.make())
    world.spawn(ECS.EntityRecipe()
        ..with(Components.Transform3D())
        ..with(Components.Mesh3D(cube))
        ..with(Components.Material3D())
    )
}

Application()
    ..add_plugin(Plugins.Window())
    ..add_plugin(Plugins.Scene3D())
    ..add_system(Application.Schedule.startup, create_scene)
    ..run()
```

Scene3D contributes its owned declarations to `GFX.Components`, `GFX.Plugins`,
and `GFX.Resources` without changing their public names. The package owns its
shaders, tone-mapping tables, model examples, tests, tools, and documentation.
See [Docs/README.md](Docs/README.md) for the complete API and rendering model.
