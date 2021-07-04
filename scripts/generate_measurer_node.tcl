# Tcl script for generating 'measurer_node' Vivado project
# based on the output of "generate_project_tcl"

# Set the origin directory to the main folder
set origin_dir [file normalize [file dirname [info script]]/..]

set part "xc7a200tsbg484-1"

# Create project
create_project measurer_node $origin_dir/projects/measurer_node -part $part

# Project properties
set obj [get_projects measurer_node]
set_property "part" $part $obj
set_property "board_part" "digilentinc.com:nexys_video:part0:1.1" $obj
set_property "default_lib" "xil_defaultlib" $obj
set_property "simulator_language" "Mixed" $obj
set_property "ip_cache_permissions" "read write" $obj
set_property -name "xpm_libraries" -value "XPM_CDC XPM_MEMORY" -objects $obj

# Create 'sources_1' fileset (if not found)
if {[string equal [get_filesets -quiet sources_1] ""]} {
  create_fileset -srcset sources_1
}

# Set 'sources_1' fileset object
set obj [get_filesets sources_1]
set files [list \
	"[file normalize "$origin_dir/src/hdl/measurer_node/measurer_node.v"]"\
	"[file normalize "$origin_dir/src/hdl/measurer_node/control_unit.v"]"\
	"[file normalize "$origin_dir/src/hdl/measurer_node/packet_analysis.v"]"\
	"[file normalize "$origin_dir/src/hdl/measurer_node/packet_gen.v"]"\
	"[file normalize "$origin_dir/src/hdl/measurer_node/measurer_def.vh"]"\
	"[file normalize "$origin_dir/src/hdl/common/mac/gig_eth_mac.v"]"\
	"[file normalize "$origin_dir/src/hdl/common/mac/gig_eth_mac_rx.v"]"\
	"[file normalize "$origin_dir/src/hdl/common/mac/gig_eth_mac_tx.v"]"\
	"[file normalize "$origin_dir/src/hdl/common/mac/CRC_chk.v"]"\
	"[file normalize "$origin_dir/src/hdl/common/mac/CRC_gen.v"]"\
	"[file normalize "$origin_dir/src/hdl/common/gmii_to_rgmii.v"]"\
	"[file normalize "$origin_dir/src/hdl/common/uart.v"]"\
	"[file normalize "$origin_dir/src/hdl/common/uart_rx.v"]"\
	"[file normalize "$origin_dir/src/hdl/common/uart_tx.v"]"\
	"[file normalize "$origin_dir/src/hdl/common/clk_gen.v"]"\
	"[file normalize "$origin_dir/src/hdl/common/counter.v"]"\
	"[file normalize "$origin_dir/src/hdl/common/memory_block.v"]"\
	"[file normalize "$origin_dir/src/hdl/common/edge_detector.v"]"\
	"[file normalize "$origin_dir/src/hdl/common/node_def.vh"]"\
]
add_files -norecurse -fileset $obj $files

# Top module
set_property "top" "measurer_node" $obj

# IP cores
set files [list \
	"[file normalize "$origin_dir/src/ip/fifo.xci"]"\
]
add_files -norecurse -fileset $obj $files

# Create 'constrs_1' fileset (if not found)
if {[string equal [get_filesets -quiet constrs_1] ""]} {
  create_fileset -constrset constrs_1
}

# Set 'constrs_1' fileset object
set obj [get_filesets constrs_1]
set file "[file normalize "$origin_dir/src/constr/NexysVideo_Master.xdc"]"
add_files -norecurse -fileset $obj $file

# Create 'synth_1' run (if not found)
if {[string equal [get_runs -quiet synth_1] ""]} {
  create_run -name synth_1 -part xc7a200tsbg484-1 -flow {Vivado Synthesis 2017} -strategy "Vivado Synthesis Defaults" -constrset constrs_1
} else {
  set_property strategy "Vivado Synthesis Defaults" [get_runs synth_1]
  set_property flow "Vivado Synthesis 2017" [get_runs synth_1]
}
set obj [get_runs synth_1]

# set the current synth run
current_run -synthesis [get_runs synth_1]

# Create 'impl_1' run (if not found)
if {[string equal [get_runs -quiet impl_1] ""]} {
  create_run -name impl_1 -part xc7a200tsbg484-1 -flow {Vivado Implementation 2017} -strategy "Vivado Implementation Defaults" -constrset constrs_1 -parent_run synth_1
} else {
  set_property strategy "Vivado Implementation Defaults" [get_runs impl_1]
  set_property flow "Vivado Implementation 2017" [get_runs impl_1]
}
set obj [get_runs impl_1]
set_property -name "steps.write_bitstream.args.readback_file" -value "0" -objects $obj
set_property -name "steps.write_bitstream.args.verbose" -value "0" -objects $obj

# set the current impl run
current_run -implementation [get_runs impl_1]

puts "Project created"