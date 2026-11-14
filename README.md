# Godot 4 – Dynamic 2D Raymarched Heightmap Shadows

A dynamic 2D shadow system for Godot 4 that generates real-time heightmaps from scene `z_index` hierarchies and uses screen-space raymarching to cast realistic directional shadows.

<img width="991" height="855" alt="HeightMapShadowScreenshot" src="https://github.com/user-attachments/assets/7df8a1c2-6ba0-48ab-a38c-d1db20156fc0" />

## Features

* **Real-Time Raymarched Shadows:** Generates accurate shadows based on object heights (`z_index`) with dynamic day/night sun rotation and shadow length scaling.
* **Broad 2D Node Support:** Automatically clones `Sprite2D`, `AnimatedSprite2D`, `MultiMeshInstance2D`, `Polygon2D`, `TileMapLayer`, `TileMap`, `MeshInstance2D`, `Line2D`, `CPUParticles2D`, and `GPUParticles2D` into an isolated `World2D` `SubViewport`.
* **Full Animation Synchronization:** Synchronizes global transforms, visibility, effective transparency (alpha), frames, textures, flips, offsets, regions, and `AnimatedSprite2D` states in real time.
* **Flexible Shadow Roles & Inheritance:** Assign shadow behavior to individual nodes or entire parent scenes (child nodes automatically inherit their parent's shadow group unless overridden).
* **Semi-Transparent ZeroShadow Overlays:** Supports translucent unshaded objects (via `modulate` or `self_modulate`), allowing underlying shadows to show through proportionally to their opacity.
* **Custom Shader Support (Wind & UV Deformations):** Seamlessly supports custom vertex and fragment shaders by switching cloned materials into heightmap silhouette mode, syncing uniforms, and automatically injecting and caching additive blend modes for ZeroShadow overlays.
* **Runtime Node Management API:** Dynamically register newly spawned entities or unregister them upon destruction, backed by automatic `tree_exiting` cleanup.
* **Static vs. Dynamic Optimization:** Separates static level geometry from moving entities so only dynamic nodes are synchronized per frame.
* **Camera & Edge Handling:** Dynamically scales raymarch distances with camera zoom and uses viewport margins to prevent shadow clipping at screen edges.

## Shadow Groups

Apply one of the following groups to any supported 2D node or its scene root:

* **`ShadowObject`**: Casts shadows and receives shadows from taller objects (stored in Red + Green channels).
* **`ShadowCastOnly`**: Casts shadows based on its `z_index` without receiving shadows itself (ideal for glowing objects, clouds, or high-altitude elements; stored in Red + Blue channels).
* **`ShadowReceiveOnly`**: Casts no shadows, but receives shadows from objects with a higher `z_index` (ideal for ground layers, paths, or elevated platforms; stored in the Green channel).
* **No Group (Default / ZeroShadow)**: Neither casts nor receives shadows. Preserves standard 2D `z_index` layering and lets underlying shadows bleed through when semi-transparent (additive Blue channel). *(Note: You can explicitly assign the `ZeroShadow` group to a child node if you need to override a shadow group inherited from its parent.)*

### Optional Performance Groups

* **`StaticShadow`**: Marks an otherwise dynamic node type (such as `Sprite2D`) as static so it is skipped during per-frame transform synchronization.
* **`DynamicShadow`**: Forces a normally static node type (such as `TileMapLayer` or `MultiMeshInstance2D`) to update every frame.

## How It Works

1. **Heightmap Pass (`SubViewport`):** Supported visual nodes are mirrored (without duplicating child nodes) into an isolated `World2D` `SubViewport` using silhouette shaders that encode their accumulated `z_index` (relative to `max_height_z`) into separate RGB channels depending on their shadow role.
2. **Raymarching Pass (`ColorRect`):** A full-screen `ColorRect` evaluates the heightmap texture per pixel, compares receiver and caster heights, accounts for semi-transparent ZeroShadow overlays, and marches toward `sun_direction` to compute shadow occlusion.

## Custom Shader Integration

To make custom shaders (such as wind sway or distortion shaders) compatible with the heightmap pass, add these three uniforms at the top of your shader:

```glsl
uniform bool heightmap_mode = false;
uniform vec4 height_color = vec4(0.0, 0.5, 0.0, 1.0);
uniform bool additive_heightmap = false;
```

At the very end of your `fragment()` function, add the following check:

```glsl
if (heightmap_mode) {
	if (COLOR.a < 0.05) { discard; }
	if (additive_heightmap) {
		COLOR = vec4(height_color.rgb * COLOR.a, 1.0);
	} else {
		COLOR = vec4(height_color.rgb, COLOR.a);
	}
}
```

The world controller automatically enables `heightmap_mode`, assigns the calculated `height_color`, injects `render_mode blend_add` (with shader caching) for ZeroShadow nodes, and keeps all other shader uniforms synchronized between the original node and its heightmap clone.

## Runtime API (Adding & Removing Objects)

When spawning or destroying entities during gameplay, call these methods on the world controller node:

**Register newly spawned nodes:**
```gdscript
world.register_shadow_node(new_enemy)
world.register_shadow_node(new_projectile, "ShadowCastOnly")
```

**Unregister nodes before freeing (also handled automatically on `tree_exiting`):**
```gdscript
world.unregister_shadow_nodes(enemy_node)
world.unregister_shadow_nodes([sprite_1, sprite_2, sprite_3])
```

## Setup and Usage

1. Open `project.godot` in Godot 4.
2. Assign `ShadowObject`, `ShadowCastOnly`, or `ShadowReceiveOnly` to supported 2D nodes (or parent nodes). Leave unassigned for default ZeroShadow behavior.
3. Configure virtual heights via `z_index` (`z_index` values from parent `CanvasItem` nodes are accumulated automatically).
4. Adjust `max_height_z`, shadow lengths, sun rotation speed, and tint colors directly in the Inspector.

## Controls

* **Mouse Wheel:** Zoom in / out
* **Esc:** Quit application

## Limitations

* **Uniform MultiMesh & TileMap Heights:** Instances within a single `MultiMeshInstance2D`, `TileMapLayer`, or `TileMap` share a uniform shadow height based on the node's `z_index`.
* **8-Bit Height Precision:** Each heightmap color channel uses 8-bit precision (255 steps). Increasing `max_height_z` provides finer height increments per `z_index` level, up to a maximum of 255 distinct height levels.

## License

MIT License.
