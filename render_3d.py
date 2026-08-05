#!/usr/bin/env python3
"""
Generate 3D chip visualization from DEF file using Blender
"""
import bpy
import bmesh
import math
import re
import sys

# Clear existing objects
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

# Parse DEF file for components and pins
def parse_def(def_path):
    components = []
    pins = []
    die_area = None
    
    with open(def_path, 'r') as f:
        content = f.read()
    
    # Get die area
    die_match = re.search(r'DIEAREA\s*\(\s*(\d+)\s+(\d+)\s*\)\s*\(\s*(\d+)\s+(\d+)\s*\)', content)
    if die_match:
        die_area = (int(die_match.group(1)), int(die_match.group(2)), 
                    int(die_match.group(3)), int(die_match.group(4)))
    
    # Get components (simplified - just count and sample positions)
    comp_section = re.search(r'COMPONENTS\s+(\d+)\s*;(.*?)END COMPONENTS', content, re.DOTALL)
    if comp_section:
        comp_count = int(comp_section.group(1))
        comp_text = comp_section.group(2)
        # Sample some placements
        placements = re.findall(r'PLACED\s*\(\s*(\d+)\s+(\d+)\s*\)', comp_text)
        for x, y in placements[:5000]:  # Limit for performance
            components.append((int(x), int(y)))
    
    # Get pins
    pin_section = re.search(r'PINS\s+(\d+)\s*;(.*?)END PINS', content, re.DOTALL)
    if pin_section:
        pin_text = pin_section.group(2)
        pin_places = re.findall(r'PLACED\s*\(\s*(\d+)\s+(\d+)\s*\)', pin_text)
        for x, y in pin_places:
            pins.append((int(x), int(y)))
    
    return die_area, components, pins

# Create materials
def create_material(name, color, metallic=0.8, roughness=0.3):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    
    output = nodes.new('ShaderNodeOutputMaterial')
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = color
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    
    mat.node_tree.links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    return mat

# Materials for different chip elements
mat_substrate = create_material("Substrate", (0.15, 0.15, 0.18, 1), 0.1, 0.8)
mat_cells = create_material("Cells", (0.4, 0.55, 0.4, 1), 0.6, 0.4)
mat_m1 = create_material("Metal1", (0.7, 0.5, 0.3, 1), 0.9, 0.2)
mat_m2 = create_material("Metal2", (0.3, 0.5, 0.7, 1), 0.9, 0.2)
mat_pins = create_material("Pins", (0.85, 0.7, 0.4, 1), 0.95, 0.15)
mat_io_ring = create_material("IO_Ring", (0.2, 0.3, 0.4, 1), 0.7, 0.3)

# Parse the DEF
def_path = "/home/kit/OpenROAD-flow-scripts/flow/results/nangate45/compute_core_v4/base/6_final.def"
die_area, components, pins = parse_def(def_path)

if die_area:
    x0, y0, x1, y1 = die_area
    # Convert from nm to reasonable units (1 unit = 10um)
    scale = 1 / 10000
    width = (x1 - x0) * scale
    height = (y1 - y0) * scale
    
    print(f"Die area: {width:.2f} x {height:.2f} units")
    print(f"Components: {len(components)}, Pins: {len(pins)}")
    
    # Create substrate (base plate)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(width/2, height/2, -0.1))
    substrate = bpy.context.active_object
    substrate.name = "Substrate"
    substrate.scale = (width * 1.05, height * 1.05, 0.2)
    substrate.data.materials.append(mat_substrate)
    
    # Create cell layer (main silicon area)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(width/2, height/2, 0.15))
    cells = bpy.context.active_object
    cells.name = "Cell_Layer"
    cells.scale = (width * 0.95, height * 0.95, 0.3)
    cells.data.materials.append(mat_cells)
    
    # Create metal routing layers with grid pattern effect
    for i, (z, mat, name) in enumerate([(0.35, mat_m1, "M1"), (0.55, mat_m2, "M2")]):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(width/2, height/2, z))
        metal = bpy.context.active_object
        metal.name = name
        metal.scale = (width * 0.92, height * 0.92, 0.15)
        metal.data.materials.append(mat)
    
    # Create I/O ring
    ring_width = width * 0.03
    for pos, rot, sx, sy in [
        ((width/2, 0, 0.25), 0, width, ring_width),  # bottom
        ((width/2, height, 0.25), 0, width, ring_width),  # top
        ((0, height/2, 0.25), 0, ring_width, height),  # left
        ((width, height/2, 0.25), 0, ring_width, height),  # right
    ]:
        bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
        ring = bpy.context.active_object
        ring.name = "IO_Ring"
        ring.scale = (sx, sy, 0.4)
        ring.data.materials.append(mat_io_ring)
    
    # Add I/O pins as small golden bumps
    pin_scale = scale
    for i, (px, py) in enumerate(pins[:200]):  # Limit pins for performance
        x = px * scale
        y = py * scale
        bpy.ops.mesh.primitive_cylinder_add(radius=0.3, depth=0.4, location=(x, y, 0.6))
        pin = bpy.context.active_object
        pin.name = f"Pin_{i}"
        pin.data.materials.append(mat_pins)
    
    # Add some MAC unit blocks to show structure
    mac_rows, mac_cols = 16, 16
    mac_width = width * 0.9 / mac_cols
    mac_height = height * 0.9 / mac_rows
    mac_margin = 0.05
    
    for row in range(mac_rows):
        for col in range(mac_cols):
            x = width * 0.05 + col * mac_width + mac_width/2
            y = height * 0.05 + row * mac_height + mac_height/2
            
            bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, 0.75))
            mac = bpy.context.active_object
            mac.name = f"MAC_{row}_{col}"
            mac.scale = (mac_width * 0.85, mac_height * 0.85, 0.3)
            
            # Alternate colors for visual interest
            if (row + col) % 2 == 0:
                mat = create_material(f"MAC_A_{row}_{col}", (0.35, 0.45, 0.55, 1), 0.7, 0.35)
            else:
                mat = create_material(f"MAC_B_{row}_{col}", (0.45, 0.55, 0.45, 1), 0.7, 0.35)
            mac.data.materials.append(mat)

# Set up camera
cam_data = bpy.data.cameras.new("Camera")
cam_obj = bpy.data.objects.new("Camera", cam_data)
bpy.context.scene.collection.objects.link(cam_obj)
bpy.context.scene.camera = cam_obj

# Position camera for isometric-ish view
cam_obj.location = (width * 1.8, -height * 0.6, width * 1.2)
cam_obj.rotation_euler = (math.radians(65), 0, math.radians(55))
cam_data.lens = 50

# Set up lighting
# Key light
light_data = bpy.data.lights.new("KeyLight", type='AREA')
light_data.energy = 2000
light_data.size = 20
light_obj = bpy.data.objects.new("KeyLight", light_data)
light_obj.location = (width * 2, -height, width * 2)
light_obj.rotation_euler = (math.radians(45), 0, math.radians(45))
bpy.context.scene.collection.objects.link(light_obj)

# Fill light
fill_data = bpy.data.lights.new("FillLight", type='AREA')
fill_data.energy = 800
fill_data.size = 15
fill_obj = bpy.data.objects.new("FillLight", fill_data)
fill_obj.location = (-width, height * 2, width * 1.5)
fill_obj.rotation_euler = (math.radians(60), 0, math.radians(-45))
bpy.context.scene.collection.objects.link(fill_obj)

# Rim light
rim_data = bpy.data.lights.new("RimLight", type='SPOT')
rim_data.energy = 1500
rim_obj = bpy.data.objects.new("RimLight", rim_data)
rim_obj.location = (width * 0.5, height * 2, width * 0.8)
rim_obj.rotation_euler = (math.radians(120), 0, math.radians(180))
bpy.context.scene.collection.objects.link(rim_obj)

# World background
world = bpy.data.worlds.new("ChipWorld")
bpy.context.scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs['Color'].default_value = (0.02, 0.02, 0.03, 1)  # Very dark blue-black

# Render settings
bpy.context.scene.render.engine = 'CYCLES'
bpy.context.scene.cycles.samples = 128
bpy.context.scene.render.resolution_x = 1920
bpy.context.scene.render.resolution_y = 1080
bpy.context.scene.render.film_transparent = False

# Output path
bpy.context.scene.render.filepath = "/home/kit/kimi_accelerator/layout_3d.png"

# Render
bpy.ops.render.render(write_still=True)
print("Render complete!")
