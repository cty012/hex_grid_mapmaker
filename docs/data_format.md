# Hex Grid Mapmaker Data Format Specification

The Hex Grid Mapmaker app saves and loads map data using a JSON-based format. This document describes the schema and coordinate system used.

## Coordinate System
We use the **Axial Coordinate System** for hex tiles, defined by `q` (column) and `r` (row).
- In a "flat-topped" orientation, `q` goes right, and `r` goes down-left.
- In a "pointy-topped" orientation, `q` goes right, and `r` goes down-right.

For any tile, a virtual `s` coordinate can be inferred using `q + r + s = 0`.

## JSON Schema

The root object describes a `HexMap`.

### HexMap
| Field         | Type     | Description                                                     |
|---------------|----------|-----------------------------------------------------------------|
| `version`     | String   | Data format version, e.g., `"1.0"`.                             |
| `orientation` | String   | `"pointy-topped"` or `"flat-topped"`. Determines rendering.     |
| `layers`      | Array    | A list of `Layer` objects.                                      |

### Layer
Layers represent hierarchical groupings. 
- **Layer 0** contains Regions made up of specific Hex Tiles.
- **Layer N (N > 0)** contains Regions made up of Regions from Layer N-1.

| Field         | Type     | Description                                                     |
|---------------|----------|-----------------------------------------------------------------|
| `index`       | Integer  | The layer index (0 is the base tile layer).                     |
| `regions`     | Array    | A list of `Region` objects contained in this layer.             |

### Region
A region is a logical grouping. For layer 0, it groups tiles. For layer N>0, it groups lower-layer regions.

| Field          | Type     | Description                                                          |
|----------------|----------|----------------------------------------------------------------------|
| `id`           | String   | Unique identifier for this region.                                   |
| `name`         | String   | Human-readable name.                                                 |
| `attributes`   | Object   | Arbitrary key-value pairs (e.g., `{"biome": "forest", "danger": 5}`).|
| `tiles`        | Array    | (Only for Layer 0). List of `TileCoordinate` objects.                |
| `childRegions` | Array    | (Only for Layer > 0). List of Region `id` strings from layer `index-1`. |

### TileCoordinate
Represents a single hex tile.

| Field         | Type     | Description                                                     |
|---------------|----------|-----------------------------------------------------------------|
| `q`           | Integer  | The axial Q coordinate.                                         |
| `r`           | Integer  | The axial R coordinate.                                         |

## Example
```json
{
  "version": "1.0",
  "orientation": "pointy-topped",
  "layers": [
    {
      "index": 0,
      "regions": [
        {
          "id": "region_0_1",
          "name": "Forest",
          "attributes": { "biome": "forest" },
          "tiles": [
            {"q": 0, "r": 0},
            {"q": 1, "r": -1}
          ]
        }
      ]
    },
    {
      "index": 1,
      "regions": [
        {
          "id": "region_1_1",
          "name": "Elf Kingdom",
          "attributes": { "faction": "elves" },
          "childRegions": ["region_0_1"]
        }
      ]
    }
  ]
}
```
