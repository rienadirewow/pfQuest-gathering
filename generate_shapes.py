#!/usr/bin/env python3
"""
Generate shape TGA textures for pfQuest-gathering addon.
Creates 32x32 RGBA TGA files with hollow shapes and glow effect.
Matches pfQuest's node.tga style: solid border with outer glow.
"""

import struct
import math
import os

SIZE = 32
CENTER = SIZE // 2


def create_tga(filename, pixels):
    """Create a 32x32 RGBA TGA file."""
    header = struct.pack(
        '<BBBHHBHHHHBB',
        0, 0, 2,        # ID, colormap, image type
        0, 0, 0,        # Colormap spec
        0, 0,           # X, Y origin
        SIZE, SIZE,     # Width, Height
        32, 0x08        # 32-bit, 8-bit alpha, origin BOTTOM-left
    )

    with open(filename, 'wb') as f:
        f.write(header)
        # TGA with bottom-left origin: write rows bottom-to-top
        for y in range(SIZE - 1, -1, -1):
            for x in range(SIZE):
                r, g, b, a = pixels[y][x]
                f.write(struct.pack('BBBB', b, g, r, a))

    print(f"Created: {filename}")


def draw_hollow_triangle_up(size=SIZE):
    """
    Draw HOLLOW triangle pointing UP (for mines).
    Structure: black outline → colored glow (no inner fill)
    """
    pixels = [[(0, 0, 0, 0) for _ in range(size)] for _ in range(size)]

    # Triangle parameters
    margin = 7
    outline_thickness = 1.0  # Thinner black line
    glow_thickness = 4.5     # More pronounced glow

    # Vertices: top-center, bottom-left, bottom-right (pointing UP)
    top = (size // 2, margin)
    bottom_left = (margin, size - margin - 1)
    bottom_right = (size - margin - 1, size - margin - 1)

    def distance_to_line(px, py, x1, y1, x2, y2):
        """Distance from point to line segment."""
        dx, dy = x2 - x1, y2 - y1
        if dx == 0 and dy == 0:
            return math.sqrt((px - x1)**2 + (py - y1)**2)
        t = max(0, min(1, ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)))
        proj_x, proj_y = x1 + t * dx, y1 + t * dy
        return math.sqrt((px - proj_x)**2 + (py - proj_y)**2)

    def point_in_triangle(px, py):
        """Check if point is inside triangle."""
        def sign(p1, p2, p3):
            return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])
        d1 = sign((px, py), top, bottom_left)
        d2 = sign((px, py), bottom_left, bottom_right)
        d3 = sign((px, py), bottom_right, top)
        has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
        has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
        return not (has_neg and has_pos)

    for y in range(size):
        for x in range(size):
            # Distance to nearest edge
            d1 = distance_to_line(x, y, top[0], top[1], bottom_left[0], bottom_left[1])
            d2 = distance_to_line(x, y, bottom_left[0], bottom_left[1], bottom_right[0], bottom_right[1])
            d3 = distance_to_line(x, y, bottom_right[0], bottom_right[1], top[0], top[1])
            min_dist = min(d1, d2, d3)

            inside = point_in_triangle(x, y)

            # Outer glow (outside the triangle)
            if not inside and min_dist <= glow_thickness:
                alpha = int(150 * (1 - min_dist / glow_thickness))
                if alpha > 10:
                    pixels[y][x] = (255, 255, 255, alpha)

            # Black outline (on the edge, both inside and outside)
            if min_dist <= outline_thickness:
                pixels[y][x] = (0, 0, 0, 255)

            # Inner glow (inside the triangle, near edge)
            if inside and min_dist > outline_thickness and min_dist <= outline_thickness + glow_thickness:
                glow_dist = min_dist - outline_thickness
                alpha = int(150 * (1 - glow_dist / glow_thickness))
                if alpha > 10:
                    pixels[y][x] = (255, 255, 255, alpha)

    return pixels


def draw_hollow_square(size=SIZE):
    """
    Draw a HOLLOW square for herbs.
    Structure: black outline → colored glow (no inner fill)
    """
    pixels = [[(0, 0, 0, 0) for _ in range(size)] for _ in range(size)]

    # Square parameters
    margin = 8
    outline_thickness = 1.0
    glow_thickness = 4.5

    # Square bounds
    left = margin
    right = size - margin - 1
    top = margin
    bottom = size - margin - 1

    for y in range(size):
        for x in range(size):
            # Distance to nearest edge of square
            inside = left <= x <= right and top <= y <= bottom

            if inside:
                # Distance to nearest edge from inside
                edge_dist = min(x - left, right - x, y - top, bottom - y)
            else:
                # Distance to nearest edge from outside
                dx = max(left - x, 0, x - right)
                dy = max(top - y, 0, y - bottom)
                edge_dist = math.sqrt(dx * dx + dy * dy) if dx > 0 or dy > 0 else 0

            # Outer glow
            if not inside and edge_dist <= glow_thickness:
                alpha = int(150 * (1 - edge_dist / glow_thickness))
                if alpha > 10:
                    pixels[y][x] = (255, 255, 255, alpha)

            # Black outline
            if inside and edge_dist <= outline_thickness:
                pixels[y][x] = (0, 0, 0, 255)
            elif not inside and edge_dist <= outline_thickness:
                pixels[y][x] = (0, 0, 0, 255)

            # Inner glow (inside, near edge) - no solid fill
            if inside and edge_dist > outline_thickness and edge_dist <= outline_thickness + glow_thickness:
                glow_dist = edge_dist - outline_thickness
                alpha = int(150 * (1 - glow_dist / glow_thickness))
                if alpha > 10:
                    pixels[y][x] = (255, 255, 255, alpha)

    return pixels


def main():
    img_dir = os.path.join(os.path.dirname(__file__), 'img')
    os.makedirs(img_dir, exist_ok=True)

    # Generate hollow triangle pointing UP for mines
    triangle_pixels = draw_hollow_triangle_up()
    create_tga(os.path.join(img_dir, 'triangle.tga'), triangle_pixels)

    # Generate hollow square for herbs
    square_pixels = draw_hollow_square()
    create_tga(os.path.join(img_dir, 'square.tga'), square_pixels)

    print("\nDone! Triangle + Square TGA files created.")


if __name__ == '__main__':
    main()
