layout = RBA::Layout::new
layout.read("/home/kit/kimi_accelerator/compute_core_v4.gds")
top = layout.top_cell

lv = RBA::LayoutView::new
lv.show_layout(layout, true)
lv.select_cell(top.cell_index, 0)
lv.zoom_fit
lv.save_image("/home/kit/kimi_accelerator/layout_v4.png", 1200, 1200)
puts "Done"
