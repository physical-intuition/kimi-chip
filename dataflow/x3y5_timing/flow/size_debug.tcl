# Debug output flops drive long nets to port buffers. Give their Q outputs
# more drive rather than altering debug latency or weakening I/O constraints.
set debug_count 0
set block [ord::get_db_block]
set debug_master [[ord::get_db] findMaster DFFR_X2]
if {$debug_master == "NULL"} {error "DFFR_X2 master not found"}
foreach inst [$block getInsts] {
  if {[string match {debug_*hash*} [$inst getName]] &&
      [string equal [[$inst getMaster] getName] DFFR_X1]} {
    puts "X3Y5 sizing debug driver [$inst getName] to DFFR_X2"
    if {![$inst swapMaster $debug_master]} {
      error "Failed to swap debug driver [$inst getName] to DFFR_X2"
    }
    incr debug_count
  }
}
if {$debug_count == 0} {error "No debug output drivers found"}
puts "X3Y5 resized $debug_count debug output flops"
detailed_placement
check_placement -verbose
estimate_parasitics -placement
