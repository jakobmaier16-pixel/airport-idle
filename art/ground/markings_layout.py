"""Layout of the markings atlas (assets/textures/markings/markings_albedo.png, 1024², RGBA).

Single source for the atlas generator (markings_atlas.py) and the preview (ground_preview.py).
Rects are pixels (x, y, w, h) with y counted from the TOP of the image, like Godot's UVs
(Godot UV = x / 1024, y / 1024). Documented for humans in markings_atlas.md.
"""
ATLAS = 1024

# Colours (sRGB hex), from docs/art_direction.md §3.
WHITE = "#E6E6E2"
YELLOW = "#E8B830"
RED = "#C8382E"
ANTHRACITE = "#2E3236"

# Real-world sizes used in the preview (metres). ICAO Annex 14 values or the minimum ICAO allows,
# rounded to what reads in the build view.
RUNWAY_WIDTH = 45.0
TAXIWAY_WIDTH = 23.0
EDGE_LINE_W = 0.9          # runway side stripe
CENTRELINE_W = 0.9         # runway centreline stripe
CENTRELINE_DASH = 30.0     # stripe length
CENTRELINE_GAP = 20.0
THRESHOLD_BAR = (30.0, 1.8)  # length along the runway, width
DIGIT = (3.0, 9.0)           # width, height of a designator character
TAXI_LINE_W = 0.3          # taxiway centreline / lead-in (ICAO min 0.15 m; 0.3 m for readability)
SAFETY_LINE_W = 0.2        # red stand safety / boundary lines
ROAD_LINE_W = 0.2          # service road edge lines, dashed terminal edge, passenger path lines
STOP_LINE_W = 0.3          # vehicle stop / give-way line before a zebra crossing
STOP_LINE_GAP = 2.0        # stop line distance before the zebra
STOP_BAR = (4.0, 0.5)      # across the lead-in line, along it
LABEL_BOX = (4.0, 2.0)
ZEBRA_W = 3.0              # crossing width (length of one bar)
ZEBRA_PERIOD = 1.0         # 0.5 m bar + 0.5 m gap
SHORT_DASH_PERIOD = 2.0    # 1 m dash + 1 m gap

# Gutters: the atlas edges (row 0-3, column 1020-1023) stay empty, so pieces that touch the
# opposite edge don't pick up colour when the texture wraps (REPEAT) or is mipmapped.
# Characters, left to right in row 0: 3.2 × 9.6 m cell (20 px/m), glyph 3 × 9 m centred.
GLYPHS = "0123456789LCR"
GLYPH_CELL = (64, 192)
GLYPH_PX_PER_M = 20.0


def glyph_rect(ch: str) -> tuple:
    i = GLYPHS.index(ch)
    return (i * GLYPH_CELL[0], 4, GLYPH_CELL[0], GLYPH_CELL[1])


# Single pieces (map the whole rect onto a quad of the stated size; edges are anti-aliased).
RECTS = {
    "label_box":     (836, 4, 184, 92),     # 4 × 2 m stand label box (yellow frame, dark fill)
    "stop_bar":      (836, 104, 184, 32),   # yellow stop bar, mapped onto 4 × 0.5 m
    "threshold_bar": (836, 144, 184, 40),   # white threshold bar ("piano key"), mapped onto 30 × 1.8 m
    # Strips: span the full atlas width, so they repeat along U (set U past 1 to tile).
    "white_line":    (0, 200, 1024, 32),    # solid white: runway edge line, road edge line
    "yellow_line":   (0, 236, 1024, 32),    # solid yellow: taxiway centreline, lead-in line
    "red_line":      (0, 272, 1024, 32),    # solid red: stand safety / boundary line
    "centre_dash":   (0, 308, 1024, 32),    # runway centreline, 1024 px = 50 m (30 m dash, 20 m gap)
    "short_dash":    (0, 344, 1024, 32),    # dashed white, 64 px period = 2 m (1 m dash, 1 m gap)
    "zebra":         (0, 380, 1024, 32),    # zebra, 32 px/m: 0.5 m bars repeat along U; V = bar length (any)
    # Landside pieces (row 416-508). Map the whole rect onto a quad of the stated size.
    "fence_mesh":    (424, 416, 128, 92),   # welded mesh fence panel, 2 × 2 m: wires 0.1 m apart, double rails every 0.2 m
    "parking_board": (556, 416, 184, 92),   # car park tariff / information board face, 2 × 1 m
    "p_sign":        (744, 416, 92, 92),    # parking sign face "P", 0.9 × 0.9 m
    "tactile_dots":  (840, 416, 88, 88),    # tactile warning field (studs), 0.6 × 0.6 m
    "tactile_ribs":  (932, 416, 88, 88),    # tactile direction field (ribs along atlas Y), 0.6 × 0.6 m
    # Quarter curves of the yellow taxi line. Arc centre = bottom-left corner of the rect.
    "taxi_curve_r20": (0, 512, 512, 512),   # 24 px/m: rect 21.33 m, radius 20 m, line 0.3 m
    "taxi_curve_r10": (512, 512, 512, 512), # 48 px/m: rect 10.67 m, radius 10 m, line 0.3 m
}
# Road-marking letters (white, tint with vertex colour), pre-elongated: cell 30 × 92 px, row 416.
# Map one cell onto ROAD_LETTER (width × length along the reading direction).
ROAD_LETTERS = "ABEFIKLPSTUXY&"
ROAD_LETTER_CELL = (30, 92)
ROAD_LETTER = (0.5, 1.6)   # m: elongated like real road lettering (read from a moving car)


def road_letter_rect(ch: str) -> tuple:
    i = ROAD_LETTERS.index(ch)
    return (i * ROAD_LETTER_CELL[0], 416, ROAD_LETTER_CELL[0], ROAD_LETTER_CELL[1])


CENTRE_DASH_PERIOD_M = 50.0
ZEBRA_STRIP_M = 32.0         # metres of zebra in one atlas width
SHORT_DASH_STRIP_M = 32.0    # metres of short dash in one atlas width
CURVES = {
    # name: (px per metre, radius in metres, rect size in metres)
    "taxi_curve_r20": (24.0, 20.0, 512 / 24.0),
    "taxi_curve_r10": (48.0, 10.0, 512 / 48.0),
}
