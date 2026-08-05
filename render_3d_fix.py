#!/usr/bin/env python3
"""
Generate 3D chip visualization from DEF file using Blender (EEVEE)
"""
import bpy
import math
import re

# Clear existing objects
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

# Parse DEF file for die area
def_path = "/home/kit/OpenROAD-flow-scripts/flow/results/nangate45/compute_core_v4/base/6_final.def"
with open(def_path, 'r') as f:
    content = f.read()

die_match = re.search(r'DIEAREA\s*\(\s*(\d+)\s+(\d+)\s*\)\s*\(\s*(\d+)\s+(\d+)\s*\)', content)
x0, y0, x1, y1 = [int(die_match.group(i)) for i in range(1,5)]
scale = 1 / 10000
width = (x1 - x0) * scale
height = (y1 - y0) * scale

# Get pin positions
pins = []
pin_section = re.search(r'PINS\s+(\d+)\s*;(.*?)END PINS', content, re.DOTALL)
if pin_section:
    pin_places = re.findall(r'PLACED\s*\(\s*(\d+)\s+(\d+)\s*\)', pin_section.group(2))
    for px, py in pin_places:
        pins.append((int(px) * scale, int(py) * scale))

print(f"Die: {width:.1f} x {height:.1f}, Pins: {len(pins)}")

# Create materials
def make_mat(name, color, metallic=0.8, roughness=0.3):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs['Base Color'].default_value = color
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    return mat

mat_base = make_mat("Base", (0.12, 0.12, 0.15, 1), 0.1, 0.8)
mat_cells = make_mat("Cells", (0.3, 0.4, 0.35, 1), 0.6, 0.4)
mat_m1 = make_mat("M1", (0.65, 0.45, 0.25, 1), 0.9, 0.2)
mat_m2 = make_mat("M2", (0.25, 0.45, 0.65, 1), 0.9, 0.2)
mat_pins = make_mat("Pins", (0.85, 0.7, 0.4, 1), 0.95, 0.15)
mat_io = make_mat("IO", (0.18, 0.25, 0.35, 1), 0.7, 0.3)
mat_mac_a = make_mat("MAC_A", (0.3, 0.4, 0.5, 1), 0.7, 0.35)
mat_mac_b = make_mat("MAC_B", (0.4, 0.5, 0.4, 1), 0.7, 0.35)

# Build chip geometry
# Substrate
bpy.ops.mesh.primitive_cube_add(size=1, location=(width/2, height/2, -0.1))
obj = bpy.context.active_object
obj.scale = (width * 1.08, height * 1.08, 0.2)
obj.data.materials.append(mat_base)

# Cell layer
bpy.ops.mesh.primitive_cube_add(size=1, location=(width/2, height/2, 0.15))
obj = bpy.context.active_object
obj.scale = (width * 0.95, height * 0.95, 0.25)
obj.data.materials.append(mat_cells)

# Metal layers
for z, mat in [(0.32, mat_m1), (0.48, mat_m2)]:
    bpy.ops.mesh.primitive_cube_add(size=1, location=(width/2, height/2, z))
    obj = bpy.context.active_object
    obj.scale = (width * 0.93, height * 0.93, 0.12)
    obj.data.materials.append(mat)

# I/O ring
rw = width * 0.035
for x, y, sx, sy in [
    (width/2, rw/2, width*1.02, rw),
    (width/2, height-rw/2, width*1.02, rw),
    (rw/2, height/2, rw, height),
    (width-rw/2, height/2, rw, height),
]:
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, 0.32))
    obj = bpy.context.active_object
    obj.scale = (sx, sy, 0.35)
    obj.data.materials.append(mat_io)

# MAC unit grid (16x16)
for row in range(16):
    for col in range(16):
        x = width*0.06 + col*(width*0.88/16) + (width*0.88/32)
        y = height*0.06 + row*(height*0.88/16) + (height*0.88/32)
        bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, 0.7))
        obj = bpy.context.active_object
        obj.scale = (width*0.88/16*0.85, height*0.88/16*0.85, 0.25)
        obj.data.materials.append(mat_mac_a if (row+col)%2==0 else mat_mac_b)

# I/O pins
for i, (px, py) in enumerate(pins[:150]):
    bpy.ops.mesh.primitive_cylinder_add(radius=0.25, depth=0.35, location=(px, py, 0.55))
    obj = bpy.context.active_object
    obj.data.materials.append(mat_pins)

# Camera
cam_data = bpy.data.cameras.new("Camera")
cam = bpy.data.objects.new("Camera", cam_data)
bpy.context.scene.collection.objects.link(cam)
bpy.context.scene.camera = cam
cam.location = (width*1.6, -height*0.5, width*1.1)
cam.rotation_euler = (math.radians(62), 0, math.radians(52))
cam_data.lens = 45

# Lights
light = bpy.data.lights.new("Key", 'AREA')
light.energy = 1500
light.size = 25
obj = bpy.data.objects.new("Key", light)
obj.location = (width*1.5, -height*0.8, width*1.5)
obj.rotation_euler = (math.radians(50), 0, math.radians(40))
bpy.context.scene.collection.objects.link(obj)

fill = bpy.data.lights.new("Fill", 'AREA')
fill.energy = 600
fill.size = 20
obj = bpy.data.objects.new("Fill", fill)
obj.location = (-width*0.5, height*1.5, width)
obj.rotation_euler = (math.radians(55), 0, math.radians(-50))
bpy.context.scene.collection.objects.link(obj)

# World background
world = bpy.data.worlds.new("World")
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs['Color'].default_value = (0.015, 0.015, 0.025, 1)

# Render with EEVEE
bpy.context.scene.render.engine = 'BLENDER_EEVEE'
bpy.context.scene.eevee.taa_render_samples = 64
bpy.context.scene.render.resolution_x = 1920
bpy.context.scene.render.resolution_y = 1080
bpy.context.scene.render.filepath = "/home/kit/kimi_accelerator/layout_3d.png"

bpy.ops.render.render(write_still=True)
print("Done!")
