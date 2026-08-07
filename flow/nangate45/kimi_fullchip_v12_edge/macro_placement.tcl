# Edge-pinned macro placement for fullchip_v12.
#
# All 8 weight banks (mem[0]) stack on the LEFT core edge, all 8 activation
# banks (mem[1]) on the RIGHT, 20 um gaps between stacked macros (the
# channel width known to pass PDN on this platform). The entire center is
# left unobstructed so the 16x16 MAC array can cluster at its natural size
# -- the v12 signoff showed the binding path is the lane-register -> array
# strip, i.e. the array's physical span.
#
# Coordinates are computed from the actual core box at runtime, so the same
# file serves any CORE_UTILIZATION.
set block [ord::get_db_block]
set core  [$block getCoreArea]
set dbu   [$block getDbUnitsPerMicron]

set mw 152.570
set mh 113.400
set gap 20.0

set cx0 [expr [$core xMin] / double($dbu)]
set cy0 [expr [$core yMin] / double($dbu)]
set cx1 [expr [$core xMax] / double($dbu)]
set cy1 [expr [$core yMax] / double($dbu)]

set n 8
set stackh [expr $n * $mh + ($n - 1) * $gap]
set y0 [expr $cy0 + (($cy1 - $cy0) - $stackh) / 2.0]
if {$y0 < $cy0} { error "core too short for 8-macro stack" }

# odb stores the yosys-escaped names with literal backslashes:
#   mem\[0\].bank\[0\].u
for {set b 0} {$b < $n} {incr b} {
    set y [expr $y0 + $b * ($mh + $gap)]
    place_macro -macro_name [format {mem\[0\].bank\[%d\].u} $b] \
        -location [list $cx0 $y] -orientation R0
    place_macro -macro_name [format {mem\[1\].bank\[%d\].u} $b] \
        -location [list [expr $cx1 - $mw] $y] -orientation R0
}
puts "edge placement done: 16 macros pinned, stack y0=$y0"
