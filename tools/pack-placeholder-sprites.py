"""Build the ZedComm placeholder sprite pack and tile definitions with Pillow."""
from io import BytesIO
from itertools import combinations
from math import hypot
from pathlib import Path
from struct import pack

from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art" / "placeholders"
CONCEPT_ART = ROOT / "art" / "first-release-concepts"
OCCUPANCY_ART = CONCEPT_ART / "occupancy-plate.png"
WEIGHT_ART = CONCEPT_ART / "weight-plate.png"
DISPLAY_ART = CONCEPT_ART / "numeric-display-blank-face.png"
FLOOR_CABINET = ROOT / "art" / "cabinet-prototypes" / "network-cabinet-floor-frame.png"
CABINET_FRAME = 466
SWITCH_FRAME = 467
SWITCH_LEAD_SET = "zedcomm_switch_01"
SWITCH_FLOOR_SET = "zedcomm_switch_floor_01"
SWITCH_MOUNTS = ((80, 183, False), (48, 183, True), (48, 199, False), (80, 199, True))
SWITCH_ART = (CONCEPT_ART / "manual-network-switch.png", CONCEPT_ART / "manual-network-switch-on.png")
OCCUPANCY_FIRST_FRAME = 419
WEIGHT_FIRST_FRAME = 425
DISPLAY_FIRST_FRAME = 431
DISPLAY_SET = "zedcomm_display_01"
WEIGHT_FACE_SET = "zedcomm_weight_face_01"
PLATE_TERMINAL_MASK = ((88, 229), (107, 218), (108, 249), (88, 249))
WEIGHT_TERMINAL_MASK = ((72, 235), (81, 231), (85, 234), (82, 237), (79, 238), (75, 241), (73, 241))
PLATE_SOCKETS = ((85, 235), (42, 235), (42, 208), (85, 208))
WEIGHT_SOCKETS = ((85, 235), (42, 235), (42, 216), (85, 216))
MEDIA = ROOT / "workshop/ZedComm/Contents/mods/ZedComm/42/media"
SET = "zedcomm_devices_01"
TILE_WIDTH, TILE_HEIGHT = 128, 256
# Width at Build 42 scale and ground-relative lower edge in the tile cell.
SPRITES = (
    ("pressure-plate", 106, 249, "ZedCommPressurePlate"),
    ("wire", 74, 240, "ZedCommSignalWire"),
    ("numeric-display", 62, 243, "ZedCommNumericDisplay"),
)


# Mirrors WireShape.lua. Each additional frame is a two-ended route or cap.
WIRE_MASKS = (0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 12)
WIRE_LANE_OFFSETS = (9, -9, 17, -17)
COLUMNS = 4
ROWS = 8
# Screen offsets for +X, +Y, -X and -Y at Build 42 scale.
WIRE_DIRECTIONS = ((32, 16), (-32, 16), (-32, -16), (32, -16))
TILE_CENTER = (64, 224)
LEAD_STROKES = ((5, "#3a2522"), (3, "#6e4037"), (1, "#946452"))


def draw_lead(image, *points):
    pen = ImageDraw.Draw(image)
    for width, color in LEAD_STROKES:
        pen.line(points, fill=color, width=width)


def ints(*values):
    return pack(f"<{len(values)}i", *values)


def pack_string(value):
    value = value.encode("ascii")
    return ints(len(value)) + value


def sprite_frame(source, width, bottom):
    with Image.open(source) as original:
        art = original.convert("RGBA")
    # Size by the visible prop instead of the near-transparent image margins.
    bounds = art.getchannel("A").point(lambda alpha: 255 if alpha >= 16 else 0).getbbox()
    if bounds is None:
        raise ValueError(f"Empty sprite: {source}")
    art = art.crop(bounds)
    height = round(art.height * width / art.width)
    art = art.resize((width, height), Image.Resampling.LANCZOS)
    return art, (TILE_WIDTH - width) // 2, bottom - height


def wire_frame(mask, offset=0):
    # At tile scale 2, adjacent centers are separated by (64, 32).
    # Each leg meets its partner at the shared diamond edge midpoint.
    center = TILE_CENTER
    ends = [(center[0] + dx, center[1] + dy)
            for bit, (dx, dy) in enumerate(WIRE_DIRECTIONS) if mask & (1 << bit)]
    if not ends:
        ends = [(54, 219), (74, 229)]
    if offset:
        start, end = ends[0], ends[1] if len(ends) == 2 else center
        dx, dy = end[0] - start[0], end[1] - start[1]
        length = hypot(dx, dy)
        shift_x, shift_y = round(-dy * offset / length), round(dx * offset / length)
        center = (center[0] + shift_x, center[1] + shift_y)
        # Keep real tile-edge endpoints aligned with the neighboring sprites.
        if mask == 0:
            ends = [(x + shift_x, y + shift_y) for x, y in ends]
    scale = 4
    art = Image.new("RGBA", (TILE_WIDTH * scale, TILE_HEIGHT * scale))
    pen = ImageDraw.Draw(art)

    def scaled(point):
        return point[0] * scale, point[1] * scale

    route = [ends[0], center, ends[1]] if len(ends) == 2 else [ends[0], center]
    if offset and mask and len(ends) == 2:
        inner = [(round((x + TILE_CENTER[0]) / 2) + shift_x,
                  round((y + TILE_CENTER[1]) / 2) + shift_y) for x, y in ends]
        route = [ends[0], inner[0], center, inner[1], ends[1]]
    for width, color in LEAD_STROKES:
        pen.line([scaled(point) for point in route], fill=color, width=width * scale, joint="curve")
    free_ends = ends if mask == 0 else [center] if len(ends) == 1 else []
    for point in free_ends:
        x, y = scaled(point)
        pen.ellipse((x - 8, y - 8, x + 8, y + 8), fill="#b09a65")
    art = art.resize((TILE_WIDTH, TILE_HEIGHT), Image.Resampling.LANCZOS)
    bounds = art.getchannel("A").getbbox()
    return art.crop(bounds), bounds[0], bounds[1]


# Direction and lane codes mirror WireShape.lua.
ROUTE_EDGE_COUNT = 20
ROUTE_LANE_SPACING = 0.18
ROUTE_INWARD = ((-1, 0), (0, -1), (1, 0), (0, 1))


def route_edge(code):
    side, lane = divmod(code, 5)
    along = 0.5 + (lane - 2) * ROUTE_LANE_SPACING
    point = ((1, along), (along, 1), (0, along), (along, 0))[side]
    return point, ROUTE_INWARD[side]


def wire_curve(first, second=None, local_port=False):
    start, inward = route_edge(first)
    if second is not None:
        end, end_inward = route_edge(second)
    else:
        end_inward = (-inward[0], -inward[1])
        end = (0.5, 0.5) if local_port else (start[0] + inward[0] * 0.5, start[1] + inward[1] * 0.5)

    def shift(point, direction, distance):
        return point[0] + direction[0] * distance, point[1] + direction[1] * distance

    start_reach, end_reach = 0.42, 0.16 if second is None else 0.42
    if second is not None and inward[0] * end_inward[0] + inward[1] * end_inward[1] == 0:
        # Scale each corner handle to its lane's turn radius. An inner
        # bend has less room than the outer bend and turns sooner.
        dx, dy = end[0] - start[0], end[1] - start[1]
        start_reach = 0.55 * abs(dx * inward[0] + dy * inward[1])
        end_reach = 0.55 * abs(dx * end_inward[0] + dy * end_inward[1])
    control = [start, shift(start, inward, start_reach),
               shift(end, end_inward, end_reach), end]
    points = []
    for i in range(25):
        t = i / 24
        weight = ((1 - t) ** 3, 3 * t * (1 - t) ** 2, 3 * t ** 2 * (1 - t), t ** 3)
        points.append(tuple(sum(p[axis] * w for p, w in zip(control, weight)) for axis in range(2)))
    return points


def routed_wire_frame(first, second=None, local_port=False):
    scale = 4
    art = Image.new("RGBA", (TILE_WIDTH * scale, TILE_HEIGHT * scale))
    pen = ImageDraw.Draw(art)

    def project(point):
        x, y = point
        return (round((64 + (x - y) * 64) * scale),
                round((224 + (x + y - 1) * 32) * scale))

    points = [project(point) for point in wire_curve(first, second, local_port)]
    for width, color in LEAD_STROKES:
        pen.line(points, fill=color, width=width * scale, joint="curve")
    if second is None:
        x, y = points[-1]
        pen.ellipse((x - 8, y - 8, x + 8, y + 8), fill="#b09a65")
    art = art.resize((TILE_WIDTH, TILE_HEIGHT), Image.Resampling.LANCZOS)
    bounds = art.getchannel("A").getbbox()
    return art.crop(bounds), bounds[0], bounds[1]


def module_frame(direction=None, same_tile=False, compact=False):
    """A low, clip-on relay housing and its lead to the wire's tile edge."""
    art = Image.new("RGBA", (TILE_WIDTH, TILE_HEIGHT))
    pen = ImageDraw.Draw(art)
    floor = TILE_CENTER
    sockets = ((73, 213), (55, 213), (53, 205), (75, 205))
    socket = (66, 216) if direction is None else sockets[direction]

    if direction is not None:
        dx, dy = WIRE_DIRECTIONS[direction]
        end = (floor[0] + dx, floor[1] + dy)
        bend = (socket[0] + dx // 4, floor[1] + dy // 2)
        lead = [socket, bend, end]
    elif same_tile:
        lead = [socket, (66, 220), floor]
    else:
        lead = []

    if compact and lead:
        dx, dy = WIRE_DIRECTIONS[direction] if direction is not None else (0, 16)
        lead = [socket, (socket[0] + dx // 4, socket[1] + dy // 4)]
    if lead:
        for width, color in LEAD_STROKES:
            pen.line(lead, fill=color, width=width, joint="curve")

    # Steel mounting clip, shaded enclosure, and recessed lid.
    pen.polygon([(58, 202), (58, 197), (64, 194), (70, 197), (70, 202)], fill="#74695a", outline="#302b26")
    pen.line([(60, 200), (60, 198), (64, 196), (68, 198)], fill="#ac9d81")
    pen.polygon([(48, 205), (64, 212), (64, 219), (48, 212)], fill="#5a5143", outline="#302b26")
    pen.polygon([(64, 212), (80, 205), (80, 212), (64, 219)], fill="#494239", outline="#302b26")
    pen.polygon([(48, 205), (64, 197), (80, 205), (64, 213)], fill="#8f826b", outline="#302b26")
    pen.polygon([(52, 205), (64, 199), (76, 205), (64, 211)], fill="#a3957a")
    pen.line([(51, 205), (64, 198), (77, 205)], fill="#c3b396")
    pen.line([(59, 203), (64, 201), (71, 204)], fill="#514b41", width=2)
    pen.point([(53, 206), (73, 206), (64, 210)], fill="#e2cfab")
    x, y = socket
    pen.ellipse((x - 3, y - 2, x + 3, y + 2), fill="#b09a65", outline="#3a3023")
    pen.point((x, y), fill="#946452" if lead else "#302822")

    bounds = art.getbbox()
    if compact:
        cropped = art.crop(bounds)
        cropped = cropped.resize((round(cropped.width * 0.7), round(cropped.height * 0.7)),
                                 Image.Resampling.LANCZOS)
        x = TILE_CENTER[0] + round((bounds[0] - TILE_CENTER[0]) * 0.7)
        y = TILE_CENTER[1] + round((bounds[1] - TILE_CENTER[1]) * 0.7)
        return cropped, x, y
    return art.crop(bounds), bounds[0], bounds[1]


def plate_body(source, terminal_mask):
    # Leave space between the plate rim and the tile edges for the lead.
    prop, x, y = sprite_frame(source, 88, 249)
    art = Image.new("RGBA", (TILE_WIDTH, TILE_HEIGHT))
    art.alpha_composite(prop, (x, y))
    # Replace the source art's fixed terminal with the opposite rim.
    mirrored = art.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    mask = Image.new("L", art.size)
    ImageDraw.Draw(mask).polygon(terminal_mask, fill=255)
    art.paste(mirrored, (0, 0), mask)
    return art


def plate_frame(body, direction=None, same_tile=False, sockets=PLATE_SOCKETS):
    art = body.copy()
    pen = ImageDraw.Draw(art)
    socket = (74, 242) if direction is None else sockets[direction]

    if direction is not None:
        dx, dy = WIRE_DIRECTIONS[direction]
        end = (TILE_CENTER[0] + dx, TILE_CENTER[1] + dy)
        lead = [socket, end]
    elif same_tile:
        lead = [socket, (73, 235), TILE_CENTER]
    else:
        lead = []
    if lead:
        for width, color in LEAD_STROKES:
            pen.line(lead, fill=color, width=width, joint="curve")
    x, y = socket
    pen.ellipse((x - 4, y - 2, x + 4, y + 2), fill="#ab986f", outline="#342c22")
    pen.line((x - 1, y, x + 1, y), fill="#865949" if lead else "#282520")

    bounds = art.getbbox()
    return art.crop(bounds), bounds[0], bounds[1]


def plate_frames(source, terminal_mask=PLATE_TERMINAL_MASK, sockets=PLATE_SOCKETS):
    body = plate_body(source, terminal_mask)
    yield plate_frame(body)
    yield plate_frame(body, same_tile=True)
    for direction in range(len(WIRE_DIRECTIONS)):
        yield plate_frame(body, direction, sockets=sockets)


def write_icon(source, target):
    icon = Image.new("RGBA", (64, 64))
    art, _, _ = sprite_frame(source, 56, 64)
    icon.alpha_composite(art, ((64 - art.width) // 2, (64 - art.height) // 2))
    icon.save(target)


def sprite_record(index, atlas_x, atlas_y, width, height, x, y, tileset=SET):
    return pack_string(f"{tileset}_{index}") + ints(atlas_x, atlas_y, width, height, x, y, TILE_WIDTH, TILE_HEIGHT)


def texture_page(name, atlas, metadata, count):
    payload = BytesIO()
    atlas.save(payload, "PNG")
    png = payload.getvalue()
    return pack_string(name) + ints(count, 1) + metadata + ints(len(png)) + png


DOOR_BASES = ((68, 194), (60, 194), (68, 198), (60, 198))
DOOR_FAR_BASES = ((116, 218), (12, 218), (116, 222), (12, 222))


def door_pages():
    pages = []
    floor = Image.new("RGBA", (2048, 1152))
    floor_records = {}
    for reverse in range(2):
        tileset = "zedcomm_door_reverse_01" if reverse else "zedcomm_door_01"
        atlas = Image.new("RGBA", (2048, 3456))
        metadata = bytearray()
        for facing in range(4):
            hinge_x, hinge_y = (DOOR_FAR_BASES if reverse else DOOR_BASES)[facing]
            mirror = facing in (1, 3)
            for locked in range(2):
                for lock in range(6):
                    for opener in range(6):
                        index = facing * 72 + locked * 36 + lock * 6 + opener
                        body = Image.new("RGBA", (48, 48))
                        pen = ImageDraw.Draw(body)
                        pen.polygon(((5, 12), (30, 5), (41, 11), (16, 18)), fill="#a4a49a", outline="#303430")
                        pen.polygon(((5, 12), (16, 18), (16, 35), (5, 29)), fill="#525951", outline="#303430")
                        pen.polygon(((16, 18), (41, 11), (41, 28), (16, 35)), fill="#7d8477", outline="#303430")
                        pen.rectangle((21, 24, 23, 26), fill="#ef9f39" if locked else "#45473b")
                        if mirror: body = ImageOps.mirror(body)
                        tile = Image.new("RGBA", (128, 256))
                        ground = Image.new("RGBA", (128, 256))
                        body_x = max(0, min(80, hinge_x - 24))
                        body_y = hinge_y - 156
                        for socket, mode in enumerate((lock, opener)):
                            x = body_x + (47 - (27 + socket * 7) if mirror else 27 + socket * 7)
                            y = body_y + 28 - socket * 2
                            pen = ImageDraw.Draw(body)
                            local_x = x - body_x
                            pen.ellipse((local_x-2, y-body_y-2, local_x+2, y-body_y+2), fill="#b48a4d" if mode else "#202922")
                            if mode:
                                lane_x = hinge_x + (socket * 3 - 2)
                                foot = (lane_x, hinge_y + 8)
                                draw_lead(tile, (x,y), (lane_x,y+8), (lane_x,hinge_y))
                                dx, dy = ((0, 0), *WIRE_DIRECTIONS)[mode-1]
                                draw_lead(ground, (lane_x,hinge_y), foot, (64+dx,224+dy))
                        ImageDraw.Draw(body).text((7 if mirror else 24, 35), "L O", fill="#d0c7aa")
                        tile.alpha_composite(body, (body_x, body_y))
                        box = tile.getbbox()
                        x, y, right, bottom = box
                        ax, ay = index % 16 * 128, index // 16 * 192
                        atlas.alpha_composite(tile.crop(box), (ax, ay))
                        metadata += sprite_record(index, ax, ay, right-x, bottom-y, x, y, tileset)
                        if locked == 0:
                            slot = facing * 72 + reverse * 36 + lock * 6 + opener
                            box = ground.getbbox() or (0, 192, 1, 193)
                            x, y, right, bottom = box
                            ax, ay = slot % 16 * 128, slot // 16 * 64
                            floor.alpha_composite(ground.crop(box), (ax, ay))
                            pages_slot = sprite_record(slot, ax, ay, right-x, bottom-y, x, y, "zedcomm_door_floor_01")
                            floor_records[slot] = pages_slot
        pages.append(texture_page(tileset + "0", atlas, metadata, 288))
    floor_metadata = b"".join(floor_records[i] for i in range(288))
    return b"".join(pages) + texture_page("zedcomm_door_floor_010", floor, floor_metadata, 288)


def contact_pages(textures):
    body_atlas = Image.new("RGBA", (1536, 1536))
    floor_atlas = Image.new("RGBA", (1536, 256))
    body_records, floor_records = [], {}
    icon = None
    for facing in range(4):
        mirror = facing in (1, 3)
        for reverse in range(2):
            hinge_x, hinge_y = (DOOR_FAR_BASES if reverse else DOOR_BASES)[facing]
            for closed in range(2):
                for mode in range(6):
                    index = facing * 24 + reverse * 12 + closed * 6 + mode
                    tile = Image.new("RGBA", (128, 256))
                    ground = Image.new("RGBA", (128, 256))
                    # The sensor sits below the actuator so both remain readable.
                    x, y = hinge_x, hinge_y - 112
                    towards_leaf = (-1 if mirror else 1) * (-1 if reverse else 1)
                    draw = ImageDraw.Draw(tile)
                    sensor = (x - 5, y, x + 4, y + 23)
                    draw.rectangle(sensor, fill="#c2bda4", outline="#373d38")
                    draw.line((x-2,y+4,x+1,y+4), fill="#737a6c", width=2)
                    draw.line((x-2,y+19,x+1,y+19), fill="#737a6c", width=2)
                    magnet_x = x + towards_leaf * (12 if closed else 22)
                    draw.rectangle((magnet_x-3,y+3,magnet_x+3,y+20), fill="#959784", outline="#373d38")
                    if mode:
                        lane_x = hinge_x - 6
                        draw_lead(tile, (x,y+23), (lane_x,y+28), (lane_x,hinge_y))
                        dx, dy = ((0,0), *WIRE_DIRECTIONS)[mode-1]
                        draw_lead(ground, (lane_x,hinge_y), (lane_x,hinge_y+8), (64+dx,224+dy))
                    box = tile.getbbox()
                    left, top, right, bottom = box
                    ax, ay = index % 12 * 128, index // 12 * 192
                    body_atlas.alpha_composite(tile.crop(box), (ax,ay))
                    body_records.append(sprite_record(index, ax,ay,right-left,bottom-top,left,top,"zedcomm_contact_01"))
                    if closed == 0:
                        slot = facing * 12 + reverse * 6 + mode
                        box = ground.getbbox() or (0,192,1,193)
                        left,top,right,bottom = box
                        ax,ay = slot % 12 * 128, slot // 12 * 64
                        floor_atlas.alpha_composite(ground.crop(box),(ax,ay))
                        floor_records[slot] = sprite_record(slot,ax,ay,right-left,bottom-top,left,top,"zedcomm_contact_floor_01")
                    if index == 6:
                        icon = tile.crop(tile.getbbox())
    icon.thumbnail((48,48),Image.Resampling.NEAREST)
    inventory = Image.new("RGBA",(64,64))
    inventory.alpha_composite(icon,((64-icon.width)//2,(64-icon.height)//2))
    inventory.save(textures / "Item_ZedCommDoorContact.png")
    return (texture_page("zedcomm_contact_010", body_atlas, b"".join(body_records), 96)
            + texture_page("zedcomm_contact_floor_010", floor_atlas,
                           b"".join(floor_records[i] for i in range(48)), 48))


def switch_page(textures):
    art = []
    for source in SWITCH_ART:
        with Image.open(source) as original:
            art.append(original.convert("RGBA"))
    boxes = [frame.getchannel("A").point(lambda alpha: 255 if alpha >= 128 else 0).getbbox() for frame in art]
    left, top = min(box[0] for box in boxes), min(box[1] for box in boxes)
    right, bottom = max(box[2] for box in boxes), max(box[3] for box in boxes)
    body = [frame.crop((left, top, right, bottom)) for frame in art]
    width = 30
    height = round(width * (bottom - top) / (right - left))
    atlas = Image.new("RGBA", (256, 64))
    metadata = bytearray()
    wired = Image.new("RGBA", (1024, 640))
    wired_metadata = bytearray()
    floor = Image.new("RGBA", (1024, 192))
    floor_metadata = bytearray()
    directions = ((0, 0), *WIRE_DIRECTIONS)

    for facing, (center, baseline, mirror) in enumerate(SWITCH_MOUNTS):
        back_edge = TILE_CENTER[1] - TILE_WIDTH // 4 + abs(center - TILE_CENTER[0]) // 2
        wall_base = (center, back_edge if facing < 2 else 2 * TILE_CENTER[1] - back_edge)
        for state, frame in enumerate(body):
            slot = facing * len(body) + state
            frame = frame.resize((width, height), Image.Resampling.LANCZOS)
            if mirror:
                frame = ImageOps.mirror(frame)
            atlas.alpha_composite(frame, (slot * width, 0))
            metadata.extend(sprite_record(SWITCH_FRAME + slot, slot * width, 0, width, height,
                                          center - width // 2, baseline - height))
            for direction, (dx, dy) in enumerate(directions):
                tile = Image.new("RGBA", (TILE_WIDTH, TILE_HEIGHT))
                socket = (center, baseline - 3)
                foot = (center, 216 if facing < 2 else 232)
                draw_lead(tile, socket, foot)
                tile.alpha_composite(frame, (center - width // 2, baseline - height))
                x, y, right, bottom = tile.getbbox()
                index = slot * len(directions) + direction
                atlas_x, atlas_y = (index % 8) * 128, (index // 8) * 128
                assert bottom - y <= 128
                wired.alpha_composite(tile.crop((x, y, right, bottom)), (atlas_x, atlas_y))
                wired_metadata.extend(sprite_record(index, atlas_x, atlas_y, right - x, bottom - y,
                                                    x, y, SWITCH_LEAD_SET))
                if state == 0:
                    tile = Image.new("RGBA", (TILE_WIDTH, TILE_HEIGHT))
                    seam = (TILE_CENTER[0] + dx, TILE_CENTER[1] + dy)
                    # Wall masks can hide the drop below the wall's projected base.
                    draw_lead(tile, wall_base, foot, seam)
                    x, y, right, bottom = tile.getbbox()
                    index = facing * len(directions) + direction
                    atlas_x, atlas_y = (index % 8) * 128, (index // 8) * 64
                    assert bottom - y <= 64
                    floor.alpha_composite(tile.crop((x, y, right, bottom)), (atlas_x, atlas_y))
                    floor_metadata.extend(sprite_record(index, atlas_x, atlas_y, right - x, bottom - y,
                                                        x, y, SWITCH_FLOOR_SET))
    icon = Image.new("RGBA", (64, 64))
    body[0].thumbnail((52, 52), Image.Resampling.LANCZOS)
    icon.alpha_composite(body[0], ((64 - body[0].width) // 2, (64 - body[0].height) // 2))
    icon.save(textures / "Item_ZedCommNetworkSwitch.png")
    count = len(SWITCH_MOUNTS) * len(body)
    return (texture_page(SET + "_switch", atlas, metadata, count)
            + texture_page(SWITCH_LEAD_SET, wired, wired_metadata, count * len(directions))
            + texture_page(SWITCH_FLOOR_SET, floor, floor_metadata, len(SWITCH_MOUNTS) * len(directions)))


def route_page(start):
    atlas = Image.new("RGBA", (1024, 2048))
    metadata = bytearray()
    index = start

    def put(art, x, y):
        nonlocal index
        slot = index - start
        row, column = divmod(slot, 8)
        atlas_x, atlas_y = column * 128, row * 64
        assert art.width <= 128 and art.height <= 64 and atlas_y + art.height <= atlas.height
        atlas.alpha_composite(art, (atlas_x, atlas_y))
        metadata.extend(sprite_record(index, atlas_x, atlas_y, art.width, art.height, x, y))
        index += 1

    for lane in range(-2, 3):
        put(*wire_frame(0, lane * 8))
    for local_port in (False, True):
        for edge in range(ROUTE_EDGE_COUNT):
            put(*routed_wire_frame(edge, local_port=local_port))
    for first, second in combinations(range(ROUTE_EDGE_COUNT), 2):
        put(*routed_wire_frame(first, second))
    assert index == OCCUPANCY_FIRST_FRAME
    for frame in plate_frames(OCCUPANCY_ART):
        put(*frame)
    assert index == WEIGHT_FIRST_FRAME
    for frame in plate_frames(WEIGHT_ART, WEIGHT_TERMINAL_MASK, WEIGHT_SOCKETS):
        put(*frame)
    return texture_page(SET + "1", atlas, metadata, index - start), index


# Face anchors in pixels within the resized casing. Update these when changing the art.
DISPLAY_WIDTH = 70
DISPLAY_BOTTOM = 243
DISPLAY_FACE_ORIGIN = (20, 24)
DISPLAY_FACE_RIGHT = (56, 15)
DISPLAY_FACE_BOTTOM = (22, 33)
DISPLAY_LED_CENTER = (62, 16)
DISPLAY_SLOT_STARTS = (3, 14, 25)

# Seven-segment strokes in a flat 8-by-9 cell, projected onto the slanted face.
DISPLAY_SEGMENTS = {
    "a": (1, 0, 7, 1.35), "b": (6.6, 0.8, 8, 4.35),
    "c": (6.6, 4.65, 8, 8.2), "d": (1, 7.65, 7, 9),
    "e": (0, 4.65, 1.4, 8.2), "f": (0, 0.8, 1.4, 4.35),
    "g": (1, 3.85, 7, 5.2),
}
DISPLAY_DIGITS = ("abcdef", "bc", "abdeg", "abcdg", "bcfg", "acdfg",
                  "acdefg", "abc", "abcdefg", "abcdfg", "g")


def display_glyph(size, slot_start, strokes, color, width_scale=1):
    scale = 4
    surface = Image.new("RGBA", (size[0] * scale, size[1] * scale))
    pen = ImageDraw.Draw(surface)
    ox, oy = DISPLAY_FACE_ORIGIN
    rx, ry = DISPLAY_FACE_RIGHT
    bx, by = DISPLAY_FACE_BOTTOM

    def project(x, y):
        u, v = (slot_start + x * width_scale) / 36, y / 9
        return (round(scale * (ox + u * (rx - ox) + v * (bx - ox))),
                round(scale * (oy + u * (ry - oy) + v * (by - oy))))

    for x0, y0, x1, y1 in strokes:
        pen.polygon([project(x0, y0), project(x1, y0), project(x1, y1), project(x0, y1)], fill=color)
    return surface.resize(size, Image.Resampling.LANCZOS)


def display_art():
    casing, x, y = sprite_frame(DISPLAY_ART, DISPLAY_WIDTH, DISPLAY_BOTTOM)
    glyphs = []
    for slot in DISPLAY_SLOT_STARTS:
        glyphs.append([
            display_glyph(casing.size, slot, (DISPLAY_SEGMENTS[segment] for segment in strokes),
                          "#bd6750" if value == 10 else "#ffb457")
            for value, strokes in enumerate(DISPLAY_DIGITS)
        ])
    led = Image.new("RGBA", casing.size)
    cx, cy = DISPLAY_LED_CENTER
    ImageDraw.Draw(led).ellipse((cx - 1, cy - 1, cx + 1, cy + 1), fill="#ffbe5a")
    return casing, x, y, glyphs, led


def legacy_display_page(start, casing, x, y, glyphs, led):
    assert start == DISPLAY_FIRST_FRAME
    atlas = Image.new("RGBA", (1024, 256))
    metadata = bytearray()
    index = start

    def put(art):
        nonlocal index
        bounds = art.getchannel("A").getbbox()
        assert bounds
        frame = art.crop(bounds)
        row, column = divmod(index - start, 8)
        atlas_x, atlas_y = column * 96, row * 48
        assert frame.width <= 96 and frame.height <= 48 and atlas_y + frame.height <= atlas.height
        atlas.alpha_composite(frame, (atlas_x, atlas_y))
        metadata.extend(sprite_record(index, atlas_x, atlas_y, frame.width, frame.height,
                                      x + bounds[0], y + bounds[1]))
        index += 1

    put(casing)
    for slot in glyphs:
        for glyph in slot:
            put(glyph)
    put(led)
    return texture_page(SET + "2", atlas, metadata, index - start), index


def display_faces_page(casing, x, y, glyphs, led):
    atlas = Image.new("RGBA", (2048, 1024))
    metadata = bytearray()
    for frame in range(257):
        face = casing.copy()
        value = frame - 1
        digits = (10, 10, 10) if value < 0 else tuple(int(digit) for digit in str(value))
        for slot, digit in enumerate(digits, start=len(glyphs) - len(digits)):
            face.alpha_composite(glyphs[slot][digit])
        if value > 0:
            face.alpha_composite(led)
        bounds = face.getchannel("A").getbbox()
        art = face.crop(bounds)
        row, column = divmod(frame, 25)
        atlas_x, atlas_y = column * 80, row * 48
        assert art.width <= 80 and art.height <= 48 and atlas_y + art.height <= atlas.height
        atlas.alpha_composite(art, (atlas_x, atlas_y))
        metadata.extend(sprite_record(frame, atlas_x, atlas_y, art.width, art.height,
                                      x + bounds[0], y + bounds[1], tileset=DISPLAY_SET))
    return texture_page(DISPLAY_SET, atlas, metadata, 257)


def weight_face_page(casing, x, y, led):
    atlas = Image.new("RGBA", (512, 128))
    metadata = bytearray()
    strokes = tuple(tuple(DISPLAY_SEGMENTS[segment] for segment in digit)
                    for digit in (*DISPLAY_DIGITS[:10], "bcefg", "ef"))

    def put(art, frame):
        bounds = art.getchannel("A").getbbox()
        assert bounds
        art = art.crop(bounds)
        row, column = divmod(frame, 20)
        atlas_x, atlas_y = column * 24, row * 24
        assert art.width <= 24 and art.height <= 24
        atlas.alpha_composite(art, (atlas_x, atlas_y))
        metadata.extend(sprite_record(frame, atlas_x, atlas_y, art.width, art.height,
                                      x + bounds[0], y + bounds[1], tileset=WEIGHT_FACE_SET))

    for slot, start in enumerate((1, 8, 15, 22, 29)):
        for index, glyph in enumerate(strokes):
            put(display_glyph(casing.size, start, glyph, "#ffb457", 0.7), slot * 12 + index)
    put(display_glyph(casing.size, 28, ((0, 7.6, 1.25, 9),), "#ffb457"), 60)
    put(led, 61)
    return texture_page(WEIGHT_FACE_SET, atlas, metadata, 62)


def main():
    atlas = Image.new("RGBA", (COLUMNS * TILE_WIDTH, ROWS * TILE_HEIGHT))
    metadata = bytearray()

    def record(index, atlas_x, atlas_y, width, height, x, y):
        metadata.extend(sprite_record(index, atlas_x, atlas_y, width, height, x, y))

    def put(index, art, x, y):
        atlas_x = (index % COLUMNS) * TILE_WIDTH + x
        atlas_y = (index // COLUMNS) * TILE_HEIGHT + y
        atlas.alpha_composite(art, (atlas_x, atlas_y))
        record(index, atlas_x, atlas_y, art.width, art.height, x, y)
        return atlas_x, atlas_y, art.width, art.height, x, y

    textures = MEDIA / "textures"
    textures.mkdir(parents=True, exist_ok=True)
    for index, (filename, width, bottom, icon_name) in enumerate(SPRITES):
        source = SOURCE / f"{filename}.png"
        put(index, *sprite_frame(source, width, bottom))
        icon_source = DISPLAY_ART if filename == "numeric-display" else source
        write_icon(icon_source, textures / f"Item_{icon_name}.png")
    write_icon(OCCUPANCY_ART, textures / "Item_ZedCommOccupancyPlate.png")
    write_icon(WEIGHT_ART, textures / "Item_ZedCommWeightPlate.png")

    for index, mask in enumerate(WIRE_MASKS, start=len(SPRITES)):
        put(index, *wire_frame(mask))

    # Frames 14–19 mirror the order in ModuleVisuals.lua.
    module_start = len(SPRITES) + len(WIRE_MASKS)
    put(module_start, *module_frame())
    put(module_start + 1, *module_frame(same_tile=True))
    for direction in range(len(WIRE_DIRECTIONS)):
        put(module_start + 2 + direction, *module_frame(direction))

    # Frames 20-25 are the floor-layer pressure plate variants.
    plate_start = module_start + 2 + len(WIRE_DIRECTIONS)
    for index, frame in enumerate(plate_frames(SOURCE / "pressure-plate.png"), start=plate_start):
        put(index, *frame)

    # Reuse the same compact pixels at several sprite origins. The registered
    # aliases keep each attachment stable through native saves.
    compact_start = plate_start + 2 + len(WIRE_DIRECTIONS)
    compact = [
        put(compact_start, *module_frame(compact=True)),
        put(compact_start + 1, *module_frame(same_tile=True, compact=True)),
    ]
    for direction in range(len(WIRE_DIRECTIONS)):
        compact.append(put(compact_start + 2 + direction, *module_frame(direction, compact=True)))

    # Mirrors ModuleVisuals.lua: three columns at each of six mount heights.
    index = compact_start + len(compact)
    for mount_y in range(152, 233, 16):
        for mount_x in (52, 64, 76):
            for atlas_x, atlas_y, width, height, x, y in compact:
                record(index, atlas_x, atlas_y, width, height,
                       x + mount_x - TILE_CENTER[0], y + mount_y - TILE_CENTER[1])
                index += 1

    # Wire variants occupy the unused upper part of the existing tile rows.
    lane_start = index
    for offset in WIRE_LANE_OFFSETS:
        for mask in WIRE_MASKS:
            slot = index - lane_start
            subrow, column = divmod(slot, COLUMNS)
            tile_row, band = divmod(subrow, 3)
            art, x, y = wire_frame(mask, offset)
            assert art.width <= TILE_WIDTH and art.height <= 60 and tile_row < ROWS
            atlas_x = column * TILE_WIDTH
            atlas_y = tile_row * TILE_HEIGHT + band * 60
            atlas.alpha_composite(art, (atlas_x, atlas_y))
            record(index, atlas_x, atlas_y, art.width, art.height, x, y)
            index += 1

    original = texture_page(SET + "0", atlas, metadata, index)
    routes, display_start = route_page(index)
    display = display_art()
    legacy_displays, count = legacy_display_page(display_start, *display)
    display_faces = display_faces_page(*display)
    weight_face = weight_face_page(display[0], display[1], display[2], display[4])
    cabinet = Image.open(FLOOR_CABINET).convert("RGBA")
    left, top, right, bottom = cabinet.getbbox()
    cropped_cabinet = cabinet.crop((left, top, right, bottom))
    cabinet_metadata = sprite_record(CABINET_FRAME, 0, 0, right - left, bottom - top, left, top)
    cabinet_page = texture_page(SET + "_cabinet", cropped_cabinet, cabinet_metadata, 1)
    switch_frames = switch_page(textures)
    write_icon(FLOOR_CABINET, textures / "Item_ZedCommSmallCabinet.png")
    packs = MEDIA / "texturepacks"
    packs.mkdir(parents=True, exist_ok=True)
    (packs / f"{SET}.pack").write_bytes(
        b"PZPK" + ints(1, 14) + original + routes + legacy_displays + display_faces + cabinet_page + switch_frames
        + weight_face + door_pages() + contact_pages(textures)
    )

    # Draw these nonblocking props in the same floor pass as vanilla overlays.
    tiles = b"tdef" + ints(1, 10) + f"{SET}\n{SET}.png\n".encode("ascii")
    assert count == CABINET_FRAME
    assert SWITCH_FRAME == CABINET_FRAME + 1
    switch_count = len(SWITCH_MOUNTS) * len(SWITCH_ART)
    tiles += ints(7, 2, 1, SWITCH_FRAME + switch_count)
    for index in range(count):
        if (module_start <= index < plate_start or compact_start <= index < lane_start
                or index > DISPLAY_FIRST_FRAME):
            tiles += ints(0)
        else:
            tiles += ints(1) + b"FloorOverlay\n\n"
    tiles += ints(0)  # Cabinet uses the ordinary object layer.
    wall_overlays = tuple(ints(2) + f"WallOverlay\n\nattached{side}\n\n".encode("ascii") for side in "NWSE")
    for props in wall_overlays:
        tiles += props * len(SWITCH_ART)
    # Build 42 reserves 512 sprite IDs per tileset. Keep saved device IDs stable.
    tiles += f"{DISPLAY_SET}\n{DISPLAY_SET}.png\n".encode("ascii")
    tiles += ints(257, 1, 2, 257)
    tiles += (ints(1) + b"FloorOverlay\n\n") * 257
    tiles += f"{SWITCH_LEAD_SET}\n{SWITCH_LEAD_SET}.png\n".encode("ascii")
    tiles += ints(8, 5, 3, switch_count * 5)
    for props in wall_overlays:
        tiles += props * (len(SWITCH_ART) * 5)
    floor_count = len(SWITCH_MOUNTS) * 5
    tiles += f"{SWITCH_FLOOR_SET}\n{SWITCH_FLOOR_SET}.png\n".encode("ascii")
    tiles += ints(8, 3, 4, floor_count)
    tiles += (ints(1) + b"FloorOverlay\n\n") * floor_count
    tiles += f"{WEIGHT_FACE_SET}\n{WEIGHT_FACE_SET}.png\n".encode("ascii")
    tiles += ints(12, 6, 5, 62)
    tiles += (ints(1) + b"FloorOverlay\n\n") * 62
    tiles += b"zedcomm_door_01\nzedcomm_door_01.png\n" + ints(16, 18, 6, 288)
    tiles += ints(0) * 288
    tiles += b"zedcomm_door_reverse_01\nzedcomm_door_reverse_01.png\n" + ints(16, 18, 7, 288)
    tiles += ints(0) * 288
    tiles += b"zedcomm_door_floor_01\nzedcomm_door_floor_01.png\n" + ints(16, 18, 8, 288)
    tiles += (ints(1) + b"FloorOverlay\n\n") * 288
    tiles += b"zedcomm_contact_01\nzedcomm_contact_01.png\n" + ints(12, 8, 9, 96)
    tiles += ints(0) * 96
    tiles += b"zedcomm_contact_floor_01\nzedcomm_contact_floor_01.png\n" + ints(12, 4, 10, 48)
    tiles += (ints(1) + b"FloorOverlay\n\n") * 48
    (MEDIA / f"{SET}.tiles").write_bytes(tiles)


if __name__ == "__main__":
    main()
