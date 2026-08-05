layout = RBA::Layout::new
layout.read("/home/kit/kimi_accelerator/compute_core_v4.gds")
top = layout.top_cell

lv = RBA::LayoutView::new
lv.show_layout(layout, true)
lv.select_cell(top.cell_index, 0)

# Set up layer properties with colors
lp = lv.each_layer.to_a

# Color scheme for Nangate45 layers
colors = {
  "M1" => 0x4169E1,    # blue
  "M2" => 0x32CD32,    # green  
  "M3" => 0xFF6347,    # red
  "M4" => 0xFFD700,    # gold
  "M5" => 0x9370DB,    # purple
  "M6" => 0x00CED1,    # cyan
  "VIA" => 0x808080,   # gray
  "POLY" => 0xFF69B4,  # pink
  "DIFF" => 0x8B4513,  # brown
  "NWELL" => 0xADD8E6, # light blue
}

lp.each do |l|
  l.visible = true
  l.fill_color = 0x4169E1  # default blue
  l.frame_color = 0x4169E1
  l.width = 1
end

lv.max_hier
lv.zoom_fit

# White background
lv.set_config("background-color", "#ffffff")

lv.save_image("/home/kit/kimi_accelerator/layout_v4_color.png", 1200, 1200)
puts "Done"
