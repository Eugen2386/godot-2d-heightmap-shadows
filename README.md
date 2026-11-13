# Godot 4 – Dynamic 2D Raymarched Heightmap Shadows

A dynamic 2D shadow system built for **Godot 4**. Instead of relying on static shadow sprites or standard 2D polygon occluders, this system generates a real-time heightmap from your scene's `z_index` hierarchy and uses a screen-space **raymarching shader** to cast realistic directional shadows across terrain and objects.

## Features

- **Real-Time Raymarched Shadows:** Casts accurate directional shadows based on object height (`z_index`).
- **Automatic Heightmap Generation:** Automatically clones sprites in the `HeightMap` and `TerrainMap` groups into a dedicated `SubViewport` without manual setup per object.
- **Camera Zoom & Edge-Margin Support:** Automatically scales raymarch distances with camera zoom and expands the heightmap viewport margin so off-screen objects still cast shadows into the view without clipping.

## How It Works

1. **Heightmap Pass (`SubViewport`):**
   - Nodes added to the `HeightMap` (objects, trees, characters) or `TerrainMap` (elevated ground) groups are automatically mirrored into a `SubViewport`.
   - Each mirrored sprite receives a lightweight silhouette shader (`silhouette.gdshader`) and is modulated based on its total `z_index` relative to `max_height_z`.
2. **Screen-Space Raymarching (`ColorRect`):**
   - A full-screen `ColorRect` inside a `CanvasLayer` reads the generated heightmap texture.
   - For every pixel on screen, the fragment shader marches toward the current `sun_direction` and compares height values to determine if the pixel is in shadow.

## Setup & Usage

1. Download or clone this repository and open `project.godot` in **Godot 4**.
2. Add any `Sprite2D` (or parent node containing a `Sprite2D`) to one of the following groups:
   - `HeightMap` – for objects that cast shadows (trees, rocks, buildings, players).
   - `TerrainMap` – for elevated terrain layers.
3. Adjust the `z_index` of your nodes to control their virtual height.
4. Customize the day/night speed, shadow lengths, tint colors, and height scaling directly in the Inspector of the main scene node.

## Controls

- **Mouse Wheel:** Zoom in and out
- **Esc:** Quit application

## Limitations

- **`Sprite2D` Only:** Currently only supports standard `Sprite2D` nodes (`AnimatedSprite2D` and `TileMapLayer` are not synchronized yet).
- **Custom Vertex Shaders:** Because cloned sprites use a dedicated silhouette material for the heightmap pass, vertex deformations on the original sprite (such as wind shaders) will not affect the cast shadow.
- **Static Scene Setup:** Heightmap clones are generated once at startup (`_ready`). Dynamically spawned nodes at runtime are not automatically added yet.

## License

This project is licensed under the **MIT License** – feel free to use, modify, and integrate it into your own Godot projects.
