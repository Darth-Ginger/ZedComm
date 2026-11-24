"""Generate the Build 42 floor cabinet meshes and shared material atlas."""

from math import cos, radians, sin, sqrt
from pathlib import Path
from runpy import run_path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "workshop/ZedComm/Contents/mods/ZedComm"
MEDIA = MOD / "42/media"
FACE_SET = "zedcomm_cabinet_faces_01"
TABLE_LEAD_SET = "zedcomm_tabletop_leads_01"
WALL_HEIGHT = 0.55
TABLETOP_SOCKET = (0, 0.038, 0.177)
# North, west, south and east. The socket aligns with the wall lead's floor anchor.
WALL_FACES = (
    ((-0.12, WALL_HEIGHT, -0.37), 0),
    ((-0.37, WALL_HEIGHT, -0.12), 90),
    ((0.12, WALL_HEIGHT, 0.37), 180),
    ((0.37, WALL_HEIGHT, 0.12), -90),
)
FACINGS = (180, -90, 0, 90)
PALETTE = (
    (158, 151, 127),  # beige enamel
    (192, 181, 151),  # beige trim
    (115, 123, 126),  # slate enamel
    (159, 170, 171),  # slate trim
    (49, 46, 40),    # chassis and feet
    (25, 26, 24),    # vents and socket recesses
    (110, 97, 75),   # connector rim
    (219, 153, 57),  # indicator
    (119, 68, 53),   # cable insulation
)
# Build 42 scales model geometry by 1.5. Leave clearance inside the collision tile.
# Name, sprite set and index, footprint (width x depth), height, sockets.
CABINETS = (
    ("SmallCabinet", "zedcomm_devices_01", 466, 0.58, 0.54, 0.54, 1),
    ("LargeCabinet", "zedcomm_cabinets_01", 0, 0.60, 0.52, 1.20, 2),
    ("XLCabinet", "zedcomm_cabinets_01", 1, 0.56, 0.54, 1.43, 3),
)


def write_texture(path):
    atlas = Image.new("RGB", (256, 16))
    draw = ImageDraw.Draw(atlas)
    for index, color in enumerate(PALETTE):
        left = 16 * index
        draw.rectangle((left, 0, left + 15, 15), fill=color)
        for dy in range(2, 14, 2):
            for dx in range(2 + dy % 3, 14, 3):
                intensity = 5 if (dx + dy) % 2 else -5
                grain = tuple(max(0, min(255, channel + intensity)) for channel in color)
                draw.point((left + dx, dy), fill=grain)
    atlas.save(path)


def cabinet_boxes(width, depth, height, sockets):
    x, z = width / 2, depth / 2
    enamel, trim = (2, 3) if sockets == 3 else (0, 1)
    boxes = []

    def box(x0, y0, z0, x1, y1, z1, material):
        boxes.append(((x0, y0, z0), (x1, y1, z1), material))

    for foot_x in (-x + 0.055, x - 0.055):
        for foot_z in (-z + 0.055, z - 0.055):
            box(foot_x - 0.032, 0, foot_z - 0.032, foot_x + 0.032, 0.052, foot_z + 0.032, 4)
    box(-x, 0.047, -z, x, 0.115, z, 4)
    box(-x + 0.014, 0.110, -z + 0.015, x - 0.014, height - 0.048, z - 0.015, enamel)
    box(-x, height - 0.056, -z, x, height, z, trim)

    front = z - 0.014
    split = sockets == 2
    panels = ((-x + 0.042, -0.010), (0.010, x - 0.042)) if split else ((-x + 0.042, x - 0.042),)
    for left, right in panels:
        top = height - (0.36 if sockets == 3 else 0.104)
        box(left, 0.15, front - 0.004, right, top, front + 0.014, trim)
        box(left + 0.014, 0.168, front + 0.012, right - 0.014, top - 0.018, front + 0.025, enamel)
        latch = right - 0.07 if left <= 0 else left + 0.06
        mid = (top + 0.16) / 2
        box(latch - 0.017, mid - 0.045, front + 0.022, latch + 0.017, mid + 0.045, front + 0.038, 4)
    rows = 3 if sockets == 3 else 2
    for row in range(rows):
        y = height - 0.14 - row * 0.063
        box(-x + 0.083, y, front + 0.026, x - 0.083, y + 0.012, front + 0.031, 5)

    # Ports sit low on the right panel beside the floor wire.
    side = x - 0.014
    for socket in range(sockets):
        port_y = 0.145 + socket * 0.067
        box(side - 0.006, port_y, -0.044, side + 0.018, port_y + 0.051, 0.044, 6)
        box(side + 0.017, port_y + 0.012, -0.030, side + 0.022, port_y + 0.039, 0.030, 5)
    box(side - 0.004, height - 0.16, 0.060, side + 0.007, height - 0.135, 0.087, 7)
    return boxes


def wall_boxes():
    return [
        ((-0.19, 0.00, -0.065), (0.19, 0.45, 0.060), 4),
        ((-0.18, 0.015, -0.049), (0.18, 0.435, 0.065), 0),
        ((-0.155, 0.048, 0.063), (0.153, 0.407, 0.080), 1),
        ((-0.145, 0.058, 0.079), (0.143, 0.397, 0.084), 0),
        ((0.104, 0.184, 0.084), (0.130, 0.256, 0.094), 4),
        ((-0.107, 0.339, 0.084), (0.096, 0.350, 0.088), 5),
        ((-0.038, -0.027, -0.025), (0.038, 0.023, 0.025), 6),
    ]


FACES = (
    ((0, 3, 2, 1), (0, 0, -1)),
    ((4, 5, 6, 7), (0, 0, 1)),
    ((0, 4, 7, 3), (-1, 0, 0)),
    ((1, 2, 6, 5), (1, 0, 0)),
    ((0, 1, 5, 4), (0, -1, 0)),
    ((3, 7, 6, 2), (0, 1, 0)),
)


def draw_preview(boxes, rotation):
    image = Image.new("RGBA", (128, 256))
    pixels = image.load()
    depth = [-float("inf")] * (128 * 256)
    yaw = radians(rotation)
    cos_yaw, sin_yaw = cos(yaw), sin(yaw)

    def project(vertex):
        x, y, z = vertex
        x, z = x * cos_yaw + z * sin_yaw, z * cos_yaw - x * sin_yaw
        return 64 + (x - z) * 52, 224 - y * 91 + (x + z) * 26, x + z + y

    def draw_triangle(a, b, c, color):
        ax, ay, az = a
        bx, by, bz = b
        cx, cy, cz = c
        divisor = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(divisor) < 1e-6:
            return
        for y in range(max(0, int(min(ay, by, cy))), min(256, int(max(ay, by, cy)) + 1)):
            for x in range(max(0, int(min(ax, bx, cx))), min(128, int(max(ax, bx, cx)) + 1)):
                p = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / divisor
                q = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / divisor
                r = 1 - p - q
                if min(p, q, r) < -1e-6:
                    continue
                distance = p * az + q * bz + r * cz
                index = y * 128 + x
                if distance > depth[index]:
                    depth[index] = distance
                    pixels[x, y] = color

    for (x0, y0, z0), (x1, y1, z1), material in boxes:
        points = [project(p) for p in corners(x0, y0, z0, x1, y1, z1)]
        for indices, (nx, ny, nz) in FACES:
            rx, rz = nx * cos_yaw + nz * sin_yaw, nz * cos_yaw - nx * sin_yaw
            if rx + ny + rz <= 0:
                continue
            shade = 0.72 + max(0, (-rx + 2 * ny + rz) / sqrt(6)) * 0.34
            color = tuple(min(255, round(channel * shade)) for channel in PALETTE[material]) + (255,)
            a, b, c, d = (points[i] for i in indices)
            draw_triangle(a, b, c, color)
            draw_triangle(a, c, d, color)
    return image


def corners(x0, y0, z0, x1, y1, z1):
    return (
        (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
        (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
    )


def write_mesh(path, boxes):
    vertices, normals, uvs, faces = [], [], [], []
    for (x0, y0, z0), (x1, y1, z1), material in boxes:
        points = corners(x0, y0, z0, x1, y1, z1)
        u0, u1 = (material * 16 + 2) / 256, (material * 16 + 14) / 256
        uv = ((u0, 0.125), (u1, 0.125), (u1, 0.875), (u0, 0.875))
        for indices, normal in FACES:
            first = len(vertices)
            vertices.extend(points[index] for index in indices)
            normals.extend((normal,) * 4)
            uvs.extend(uv)
            faces.append(tuple(range(first, first + 4)))

    def xyz(values):
        return [";".join(f"{value:.6f}" for value in row) + ";" for row in values]

    def rows(values):
        return f"  {len(values)};\n  " + ",\n  ".join(values) + ";\n"

    polygons = rows(["4;" + ",".join(map(str, face)) + ";" for face in faces])
    mesh = "xof 0303txt 0032\n\nMesh Cabinet {\n"
    mesh += rows(xyz(vertices)) + polygons
    mesh += " MeshNormals {\n" + rows(xyz(normals)) + polygons + " }\n"
    mesh += " MeshTextureCoords {\n" + rows(xyz(uvs)) + " }\n}\n"
    path.write_text(mesh, encoding="ascii", newline="\n")


def main():
    meshes = MEDIA / "models_X/ZedComm"
    textures = MEDIA / "textures/Models/ZedComm"
    mappings = MOD / "common/media/spriteModels.txt"
    for directory in (meshes, textures, mappings.parent):
        directory.mkdir(parents=True, exist_ok=True)

    write_texture(textures / "CabinetMaterials.png")
    models = {}
    tiles = {}
    previews = []
    origin = (0.0, 0.0, 0.0)
    for name, tileset, index, width, depth, height, sockets in CABINETS:
        boxes = cabinet_boxes(width, depth, height, sockets)
        models[name] = boxes
        tiles.setdefault(tileset, []).append((index, name, 0, origin))
        for rotation in FACINGS:
            tiles.setdefault(FACE_SET, []).append((len(previews), name, rotation, origin))
            previews.append(draw_preview(boxes, rotation))

    models["TabletopCabinet"] = cabinet_boxes(0.54, 0.33, 0.28, 1)
    x, y, z = TABLETOP_SOCKET
    models["TabletopCabinet"].extend((
        ((x - 0.026, y - 0.021, z - 0.017), (x + 0.026, y + 0.021, z + 0.010), 6),
        ((x - 0.013, y - 0.013, z + 0.009), (x + 0.013, y + 0.013, z + 0.012), 5),
    ))
    models["WallCabinet"] = wall_boxes()
    models["WiredWallCabinet"] = models["WallCabinet"] + [
        ((-0.009, -WALL_HEIGHT / 1.5, -0.009), (0.009, 0, 0.009), 8),
    ]
    cabinet_tiles = tiles["zedcomm_cabinets_01"]
    cabinet_tiles.append((2, "TabletopCabinet", 0, origin))
    for index, (translation, rotation) in enumerate(WALL_FACES):
        cabinet_tiles.append((3 + index, "WallCabinet", rotation, translation))
        cabinet_tiles.append((7 + index, "WiredWallCabinet", rotation, translation))

    scripts = ["module ZedComm\n{"]
    for name, boxes in models.items():
        write_mesh(meshes / f"{name}.x", boxes)
        scripts.append(f"""
    model {name}World
    {{
        mesh = ZedComm/{name},
        texture = Models/ZedComm/CabinetMaterials,
        scale = 1.0,
    }}""".lstrip("\n"))
    scripts.append("}")
    (MEDIA / "scripts/zedcomm_cabinet_models.txt").write_text("\n".join(scripts) + "\n", encoding="ascii", newline="\n")

    data = ["spriteModel\n{\n    VERSION = 1,"]
    for tileset, models in tiles.items():
        data.append(f"\n    tileset\n    {{\n        name = {tileset},")
        for index, name, rotation, (x, y, z) in models:
            # spriteModels.txt addresses sprite indices in rows of eight.
            data.append(f"""
        tile
        {{
            xy = {index % 8} {index // 8},
            modelScript = ZedComm.{name}World,
            translate = {x:.3f} {y:.3f} {z:.3f},
            rotate = 0.0 {rotation:.1f} 0.0,
            scale = 1.0,
        }}""")
        data.append("    }")
    data.append("}")
    mappings.write_text("\n".join(data) + "\n", encoding="ascii", newline="\n")
    write_preview_pack(previews)


def write_preview_pack(previews):
    packer = run_path(ROOT / "tools/pack-placeholder-sprites.py")
    ints, sprite_record, texture_page = (packer[key] for key in ("ints", "sprite_record", "texture_page"))
    atlas = Image.new("RGBA", (8 * 128, 2 * 256))
    metadata = bytearray()
    for index, preview in enumerate(previews):
        x, y = index % 8 * 128, index // 8 * 256
        atlas.alpha_composite(preview, (x, y))
        metadata += sprite_record(index, x, y, 128, 256, 0, 0, FACE_SET)
    table_page, table_count = tabletop_lead_page(packer)
    (MEDIA / "texturepacks" / f"{FACE_SET}.pack").write_bytes(
        b"PZPK" + ints(1, 2) + texture_page(FACE_SET, atlas, metadata, len(previews)) + table_page
    )
    tiles = b"tdef" + ints(1, 2) + f"{FACE_SET}\n{FACE_SET}.png\n".encode("ascii")
    tiles += ints(8, 2, 1, len(previews)) + (ints(1) + b"solidtrans\n\n") * len(previews)
    tiles += f"{TABLE_LEAD_SET}\n{TABLE_LEAD_SET}.png\n".encode("ascii")
    tiles += ints(16, 20, 2, table_count) + ints(0) * table_count
    (MEDIA / f"{FACE_SET}.tiles").write_bytes(tiles)


def tabletop_lead_page(packer):
    sprite_record, texture_page = packer["sprite_record"], packer["texture_page"]
    draw_lead = packer["draw_lead"]
    directions = ((0, 0), *packer["WIRE_DIRECTIONS"])
    center_x, center_y = packer["TILE_CENTER"]
    x, y, z = TABLETOP_SOCKET
    # The sprite atlas uses 2x pixels. Mesh size is scaled by the game's 1.5 transform.
    socket_x = center_x + round((x - z) * 64 * 1.5)
    socket_y = center_y + round(((x + z) * 32 - y * 192 / sqrt(6)) * 1.5)
    columns, cell_width, cell_height = 32, 64, 152
    atlas = Image.new("RGBA", (columns * cell_width, 10 * cell_height))
    metadata = bytearray()
    index = 0
    for surface_height in range(1, 65):
        height = surface_height * 2
        for dx, dy in directions:
            tile = Image.new("RGBA", (128, 256))
            seam = (center_x + dx, center_y + dy)
            riser = (center_x + round(dx * 0.875), center_y + round(dy * 0.875))
            draw_lead(tile, seam, riser, (riser[0], riser[1] - height), (socket_x, socket_y - height))
            x, y, right, bottom = tile.getbbox()
            atlas_x, atlas_y = (index % columns) * cell_width, (index // columns) * cell_height
            assert right - x <= cell_width and bottom - y <= cell_height
            atlas.alpha_composite(tile.crop((x, y, right, bottom)), (atlas_x, atlas_y))
            metadata += sprite_record(index, atlas_x, atlas_y, right - x, bottom - y, x, y, TABLE_LEAD_SET)
            index += 1
    return texture_page(TABLE_LEAD_SET, atlas, metadata, index), index


if __name__ == "__main__":
    main()
