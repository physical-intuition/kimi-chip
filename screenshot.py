import pya

layout = pya.Layout()
layout.read("/home/kit/kimi_accelerator/compute_core_v4.gds")
top = layout.top_cell()

lv = pya.LayoutView()
cv_index = lv.create_layout(True)
lv.cellview(cv_index).layout.assign(layout)
lv.cellview(cv_index).cell = top

lv.max_hier()
lv.zoom_fit()
lv.save_image("/home/kit/kimi_accelerator/layout_v4.png", 1200, 1200)
print("Done")
