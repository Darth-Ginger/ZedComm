#!/usr/bin/env python3
"""Draws workshop/ZedComm/preview.png: 256x256 pixel art, no dependencies.

A pressure plate sends the byte 0x5A over an eight-line cable to a display,
under the ZEDCOMM title. Drawn on a 128x128 grid and scaled 2x so the pixels
stay crisp. Rerun after editing to regenerate the image.
"""
import struct
import zlib
from pathlib import Path

GRID, SCALE = 128, 2
OUT = Path(__file__).resolve().parent.parent / "workshop/ZedComm/preview.png"

BG = (16, 22, 17)
GRID_DOT = (28, 38, 30)
FRAME = (60, 84, 64)
TITLE = (124, 252, 154)
SHADOW = (20, 60, 32)
STEEL = (96, 104, 100)
STEEL_DARK = (58, 64, 61)
STEEL_LIGHT = (150, 158, 152)
LIT = (255, 176, 46)
LIT_GLOW = (110, 70, 20)
DIM = (52, 46, 36)
SCREEN = (8, 14, 10)
DIGIT = (255, 92, 70)
MUTED = (92, 120, 96)

FONT = {  # 5x7 glyphs, rows top to bottom
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "x": ["00000", "00000", "10001", "01010", "00100", "01010", "10001"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
}

px = [[BG] * GRID for _ in range(GRID)]


def put(x, y, color):
    if 0 <= x < GRID and 0 <= y < GRID:
        px[y][x] = color


def rect(x0, y0, x1, y1, color):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            put(x, y, color)


def text(s, x, y, color, scale=1, shadow=None):
    for i, ch in enumerate(s):
        for row, bits in enumerate(FONT[ch]):
            for col, bit in enumerate(bits):
                if bit == "1":
                    gx, gy = x + (i * 6 + col) * scale, y + row * scale
                    if shadow:
                        rect(gx + 1, gy + 1, gx + scale, gy + scale, shadow)
                    rect(gx, gy, gx + scale - 1, gy + scale - 1, color)


def text_width(s, scale=1):
    return (len(s) * 6 - 1) * scale


# Background grid and frame
for y in range(4, GRID, 8):
    for x in range(4, GRID, 8):
        put(x, y, GRID_DOT)
rect(0, 0, GRID - 1, 1, FRAME); rect(0, GRID - 2, GRID - 1, GRID - 1, FRAME)
rect(0, 0, 1, GRID - 1, FRAME); rect(GRID - 2, 0, GRID - 1, GRID - 1, FRAME)

# Title
title = "ZEDCOMM"
text(title, (GRID - text_width(title, 2)) // 2, 12, TITLE, 2, SHADOW)

BYTE = 0x5A
bits = [(BYTE >> (7 - i)) & 1 for i in range(8)]

# Pressure plate (sender)
rect(8, 52, 34, 78, STEEL_DARK)
rect(10, 54, 32, 76, STEEL)
rect(13, 57, 29, 73, STEEL_LIGHT)
rect(14, 58, 28, 72, STEEL)
for y in (61, 65, 69):
    rect(16, y, 26, y, STEEL_DARK)

# Eight-line cable, one line per bit, most significant on top
for i, bit in enumerate(bits):
    y = 56 + i * 2 + (i // 4)
    rect(35, y, 91, y, LIT if bit else DIM)
for x in (35, 91):  # cable clamps
    rect(x, 53, x + 1, 75, STEEL_DARK)

# Display (receiver) showing the value
rect(92, 50, 120, 80, STEEL_DARK)
rect(94, 52, 118, 78, SCREEN)
text("90", 95 + (23 - text_width("90", 2)) // 2 + 1, 58, DIGIT, 2)

# Bit LEDs under the cable
for i, bit in enumerate(bits):
    x = 30 + i * 9
    if bit:
        rect(x - 1, 89, x + 4, 94, LIT_GLOW)
        rect(x, 90, x + 3, 93, LIT)
    else:
        rect(x, 90, x + 3, 93, DIM)

# Footer
text("0x5A", 8, 112, MUTED)
text("B42", GRID - 8 - text_width("B42"), 112, MUTED)


def png(pixels, scale):
    size = len(pixels) * scale
    raw = bytearray()
    for row in pixels:
        line = b"".join(bytes(c) * scale for c in row)
        for _ in range(scale):
            raw += b"\x00" + line

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


OUT.write_bytes(png(px, SCALE))
print(f"wrote {OUT} ({GRID * SCALE}x{GRID * SCALE})")
