#!/usr/bin/env python3
"""3D chip visualization - dramatic version"""
import bpy
import math

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

width, height = 10, 10

def make_mat(name, color, metallic=0.7, roughness=0.3):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs['Base Color'].default_value = color
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    return mat

# Bright colors
mat_base = make_mat("Base", (0.12, 0.12, 0.15, 1), 0.1, 0.8)
mat_silicon = make_mat("Silicon", (0.2, 0.45, 0.35, 1), 0.3, 0.5)
mat_m1 = make_mat("M1", (0.95, 0.6, 0.25, 1), 0.9, 0.15)
mat_m2 = make_mat("M2", (0.35, 0.6, 0.95, 1), 0.9, 0.15)
mat_m3 = make_mat("M3", (0.7, 0.4, 0.8, 1), 0.9, 0.2)
mat_pins = make_mat("Pins", (1.0, 0.9, 0.4, 1), 0.95, 0.1)
mat_io = make_mat("IO", (0.25, 0.35, 0.55, 1), 0.6, 0.4)
mat_mac_a = make_mat("MAC_A", (0.3, 0.55, 0.7, 1), 0.5, 0.4)
mat_mac_b = make_mat("MAC_B", (0.55, 0.7, 0.5, 1), 0.5, 0.4)

# Substrate
bpy.ops.mesh.primitive_cube_add(size=1, location=(width/2, height/2, -0.3))
obj = bpy.context.active_object
obj.scale = (width * 1.15, height * 1.15, 0.6)
obj.data.materials.append(mat_base)

# Silicon
bpy.ops.mesh.primitive_cube_add(size=1, location=(width/2, height/2, 0.5))
obj = bpy.context.active_object
obj.scale = (width * 0.96, height * 0.96, 1.0)
obj.data.materials.append(mat_silicon)

# Metal layers
for i, (z, mat) in enumerate([(1.2, mat_m1), (1.8, mat_m2), (2.4, mat_m3)]):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(width/2, height/2, z))
    obj = bpy.context.active_object
    obj.scale = (width * (0.94 - i*0.02), height * (0.94 - i*0.02), 0.4)
    obj.data.materials.append(mat)

# I/O ring
rw = 0.55
for x, y, sx, sy in [
    (width/2, rw/2, width*1.06, rw),
    (width/2, height-rw/2, width*1.06, rw),
    (rw/2, height/2, rw, height),
    (width-rw/2, height/2, rw, height),
]:
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, 1.5))
    obj = bpy.context.active_object
    obj.scale = (sx, sy, 1.5)
    obj.data.materials.append(mat_io)

# MAC grid
cell_w = width * 0.84 / 16
cell_h = height * 0.84 / 16
for row in range(16):
    for col in range(16):
        x = width*0.08 + col*cell_w + cell_w/2
        y = height*0.08 + row*cell_h + cell_h/2
        bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, 3.2))
        obj = bpy.context.active_object
        obj.scale = (cell_w*0.78, cell_h*0.78, 1.0)
        obj.data.materials.append(mat_mac_a if (row+col)%2==0 else mat_mac_b)

# Pins
for i in range(20):
    for edge in range(4):
        if edge == 0:
            px, py = width*0.12 + i*(width*0.76/19), 0.35
        elif edge == 1:
            px, py = width*0.12 + i*(width*0.76/19), height-0.35
        elif edge == 2:
            px, py = 0.35, height*0.12 + i*(height*0.76/19)
        else:
            px, py = width-0.35, height*0.12 + i*(height*0.76/19)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.18, depth=0.7, location=(px, py, 2.7))
        obj = bpy.context.active_object
        obj.data.materials.append(mat_pins)

# Camera
cam_data = bpy.data.cameras.new("Camera")
cam = bpy.data.objects.new("Camera", cam_data)
bpy.context.scene.collection.objects.link(cam)
bpy.context.scene.camera = cam
cam.location = (width*1.7, -height*0.6, width*1.3)
cam.rotation_euler = (math.radians(52), 0, math.radians(58))
cam_data.lens = 32

# Lights - much brighter
light = bpy.data.lights.new("Key", 'AREA')
light.energy = 20000
light.size = 50
obj = bpy.data.objects.new("Key", light)
obj.location = (width*1.8, -height*0.8, width*2.2)
obj.rotation_euler = (math.radians(38), 0, math.radians(42))
bpy.context.scene.collection.objects.link(obj)

fill = bpy.data.lights.new("Fill", 'AREA')
fill.energy = 12000
fill.size = 40
obj = bpy.data.objects.new("Fill", fill)
obj.location = (-width*0.5, height*2, width*1.5)
obj.rotation_euler = (math.radians(48), 0, math.radians(-42))
bpy.context.scene.collection.objects.link(obj)

rim = bpy.data.lights.new("Rim", 'AREA')
rim.energy = 6000
rim.size = 25
obj = bpy.data.objects.new("Rim", rim)
obj.location = (width*0.5, height*2.8, width*0.3)
bpy.context.scene.collection.objects.link(obj)

# Background
world = bpy.data.worlds.new("World")
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs['Color'].default_value = (0.015, 0.018, 0.028, 1)

# Render
bpy.context.scene.render.engine = 'BLENDER_EEVEE'
bpy.context.scene.eevee.taa_render_samples = 128
bpy.context.scene.render.resolution_x = 1920
bpy.context.scene.render.resolution_y = 1080
bpy.context.scene.render.filepath = "/home/kit/kimi_accelerator/layout_3d.png"
bpy.ops.render.render(write_still=True)
print("Done!")
