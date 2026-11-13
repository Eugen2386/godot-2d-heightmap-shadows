# Godot 4 – Dynamic 2D Raymarched Heightmap Shadows

A dynamic 2D shadow system for **Godot 4** that generates real-time heightmaps from scene `z_index` hierarchies and uses screen-space raymarching to cast realistic directional shadows.

<img width="991" height="855" alt="HeightMapShadowScreenshot" src="https://github.com/user-attachments/assets/7df8a1c2-6ba0-48ab-a38c-d1db20156fc0" />

## Features

- **Real-Time Raymarched Shadows:** Generates accurate directional shadows derived from object heights (`z_index`) with dynamic day/night sun rotation and shadow length scaling.
- **Broad 2D Node Support:** Automatically clones `Sprite2D`, `AnimatedSprite2D`, `MultiMeshInstance2D`, `Polygon2D`, `TileMapLayer`, `TileMap`, `MeshInstance2D`, `Line2D`, `CPUParticles2D`, and `GPUParticles2D` nodes into a dedicated `SubViewport`.
- **Flexible Shadow Roles (Per-Node):** Assign shadow behavior directly to individual visual nodes without parent inheritance, allowing mixed shadow elements inside complex entities (e.g., a character with a glowing, unshaded aura).
- **Automatic Zero-Shadow Handling:** Ungrouped visual nodes automatically render unshaded without casting shadows or obstructing shadows cast by objects behind them.
- **Camera & Edge Handling:** Scales raymarch distances dynamically with camera zoom and utilizes viewport margins to prevent off-screen shadow clipping.

## Shadow Groups

Assign one of the following groups directly to any supported 2D visual node:

- **`ShadowObject`** – Casts shadows and receives shadows from higher objects (stored in Red + Green channels).
- **`ShadowCastOnly`** – Casts shadows based on its `z_index` without receiving shadows itself, ideal for glowing objects, clouds, or high-altitude elements (stored in Red + Blue channels).
- **`ShadowReceiveOnly`** – Does not cast shadows, but receives shadows from objects with a higher `z_index`, ideal for ground layers, paths, or elevated platforms (stored in Green channel).
- *(No Group / Default)* – **Zero-Shadow**: Neither casts nor receives shadows, preserving standard 2D `z_index` layering without interfering with underlying shadows (additive Blue channel).

## How It Works

1. **Heightmap Pass (`SubViewport`):** Supported visual nodes are mirrored into a `SubViewport` using silhouette shaders that encode their accumulated `z_index` (relative to `max_height_z`) into separate RGB channels depending on their assigned shadow group.
2. **Raymarching Pass (`ColorRect`):** A full-screen `ColorRect` evaluates the heightmap texture per pixel, comparing receiver and caster heights while marching toward `sun_direction` to calculate shadow occlusion.

## Setup & Usage

1. Open `project.godot` in **Godot 4**.
2. Assign supported 2D visual nodes to `ShadowObject`, `ShadowCastOnly`, or `ShadowReceiveOnly` (leave ungrouped for Zero-Shadow).
3. Configure virtual heights via `z_index` (parent `CanvasItem` `z_index` values are automatically accumulated).
4. Adjust `max_height_z`, shadow lengths, sun rotation speed, and tint colors directly in the Inspector.

## Controls

- **Mouse Wheel:** Zoom in / out
- **Esc:** Quit application

## Limitations

- **Custom Vertex Shaders:** Cloned silhouette materials do not inherit custom vertex deformations (such as wind shaders).
- **Uniform MultiMesh & TileMap Heights:** Instances within a single `MultiMeshInstance2D`, `TileMapLayer`, or `TileMap` share a unified shadow height based on the node's `z_index`.
- **Static Initialization:** Heightmap clones are generated on `_ready()` and do not automatically track dynamically spawned runtime nodes yet.
- **8-Bit Height Precision:** Each heightmap color channel uses 8-bit precision (255 steps). Increasing `max_height_z` provides finer height steps per `z_index` level, up to a maximum of 255 distinct height layers.

## License

MIT License.

