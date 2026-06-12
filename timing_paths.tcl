project_open Apple-IIgs
create_timing_netlist
read_sdc
update_timing_netlist

set f [open "timing_paths_report.txt" w]

puts $f "=== Worst 30 setup paths: clk_114 (general\[0\]) domain ==="
foreach_in_collection path [get_timing_paths -to_clock {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk} -setup -npaths 30] {
    puts $f [format "slack %8.3f  DATA %7.3f  from_clk %s" [get_path_info $path -slack] [get_path_info $path -data_delay] [get_path_info $path -from_clock]]
    puts $f [format "   FROM: %s" [get_node_info [get_path_info $path -from] -name]]
    puts $f [format "   TO:   %s" [get_node_info [get_path_info $path -to] -name]]
}

puts $f ""
puts $f "=== Worst 40 setup paths: clk_sys (general\[4\]) domain ==="
foreach_in_collection path [get_timing_paths -to_clock {emu|pll|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk} -setup -npaths 40] {
    puts $f [format "slack %8.3f  DATA %7.3f  from_clk %s" [get_path_info $path -slack] [get_path_info $path -data_delay] [get_path_info $path -from_clock]]
    puts $f [format "   FROM: %s" [get_node_info [get_path_info $path -from] -name]]
    puts $f [format "   TO:   %s" [get_node_info [get_path_info $path -to] -name]]
}

close $f
project_close
