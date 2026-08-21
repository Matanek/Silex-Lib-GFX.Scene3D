# Scene3D tone-mapping LUTs

These compact RGBA16F textures preserve the validated NKEngineV1 tone-mapping
pipeline. They are generated from Blender's OpenColorIO color-management LUTs
archived in the Silex workspace, then embedded into GFX executables through
`GFX.Scene3D.ToneMapping.Tables`. Applications do not deploy these files beside
their executable.

- `AgXBase.rgba16f`: 57 x 57 x 57 AgX base transform.
- `PBRNeutral.rgba16f`: 57 x 57 x 57 Khronos PBR Neutral transform.
- `FilmicDesaturation.rgba16f`: 33 x 33 x 33 Filmic desaturation transform.
- `FilmicLooks.rgba16f`: 4096 x 7 Filmic contrast transforms.

Run `Tools/GenerateToneMappingLUTs.py` from the package to reproduce them.
Their public usage is documented in `Docs/README.md`.
