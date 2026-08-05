# Load layout with layer properties file
layout = RBA::Layout::new
layout.read("/home/kit/kimi_accelerator/compute_core_v4.gds")
top = layout.top_cell

lv = RBA::LayoutView::new
lv.show_layout(layout, true)
lv.select_cell(top.cell_index, 0)

# Load layer properties for colors
lv.load_layer_props("/home/kit/OpenROAD-flow-scripts/flow/platforms/nangate45/FreePDK45.lyp")

lv.max_hier
lv.zoom_fit

# Set white background
lv.set_config("background-color", "#ffffff")
lv.set_config("grid-visible", "false")

lv.save_image("/home/kit/kimi_accelerator/layout_v4_nice.png", 1600, 1600)
puts "Done"
