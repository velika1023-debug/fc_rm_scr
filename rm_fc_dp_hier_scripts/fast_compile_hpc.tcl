##########################################################################################
# Tool: Fusion Compiler 
# Script: fast_compile_hpc.tcl
# Version: V-2023.12-SP4
# Copyright (C) 2014-2024 Synopsys, Inc. All rights reserved.
##########################################################################################

source ./rm_utilities/procs_global.tcl 
source ./rm_utilities/procs_fc.tcl 
rm_source -file ./rm_setup/design_setup.tcl
rm_source -file ./rm_setup/fc_dp_setup.tcl
rm_source -file ./rm_setup/fc_setup.tcl
rm_source -file ./rm_setup/header_fc_dp.tcl
if {[file exists [which config_setup.tcl]]} {
	rm_source -file config_setup.tcl -after_file technology_override.tcl
} else {
	rm_source -file sidefile_setup.tcl -after_file technology_override.tcl
}
if {$HPC_CORE != ""} {
	rm_source -file ./flow_override.tcl
	rm_source -file ./rm_hpc_core_scripts/design_config.tcl
}

set PREVIOUS_STEP $INIT_DESIGN_BLOCK_NAME
set CURRENT_STEP  $FAST_COMPILE_HPC_BLOCK_NAME
set REPORT_PREFIX $CURRENT_STEP
file mkdir ${REPORTS_DIR}/${REPORT_PREFIX}
puts "RM-info: PREVIOUS_STEP = $PREVIOUS_STEP"
puts "RM-info: CURRENT_STEP  = $CURRENT_STEP"
puts "RM-info: REPORT_PREFIX = $REPORT_PREFIX"

redirect -tee -file ${REPORTS_DIR}/${REPORT_PREFIX}/run_start.rpt {run_start}

set_svf ${OUTPUTS_DIR}/${FAST_COMPILE_HPC_BLOCK_NAME}.svf

rm_source -file $TCL_PVT_CONFIGURATION_FILE -optional -print "TCL_PVT_CONFIGURATION_FILE"

########################################################################
## Open design
########################################################################
set DESIGN_VIEW "design" 

rm_open_design -from_lib      ${WORK_DIR}/${DESIGN_LIBRARY} \
               -block_name    $DESIGN_NAME \
               -from_label    $PREVIOUS_STEP \
               -to_label      $CURRENT_STEP \
               -view          $DESIGN_VIEW \
	       -dp_block_refs $SUB_BLOCK_REFS

## Set Design Planning Flow Strategy
rm_set_dp_flow_strategy -dp_stage $DP_STAGE -dp_flow hierarchical -hier_fp_style $FLOORPLAN_STYLE

## Set active scenarios for the step
if {$FAST_COMPILE_HPC_ACTIVE_SCENARIO_LIST != ""} {
	set_scenario_status -active false [get_scenarios -filter active]
	set_scenario_status -active true $FAST_COMPILE_HPC_ACTIVE_SCENARIO_LIST
}
if {$HPC_CORE != "" } {current_scenario $FMAX_SCENARIO}

#################################################################################
## Insert DFT
#################################################################################
if {$HPC_CORE != "" } {
  if { $DFT_INSERT_ENABLE } {
    # Don't need to enable DFT during this step
    # DFT Constraints for fast compile
    if {[file exists [which $DFT_FAST_COMPILE_HPC_SCRIPT]]} {
      puts "RM-info: Loading : [which $DFT_FAST_COMPILE_HPC_SCRIPT]"
      rm_source -file $DFT_FAST_COMPILE_HPC_SCRIPT -optional -print "DFT_FAST_COMPILE_HPC_SCRIPT"  
    } elseif {$DFT_PORTS_FILE != ""} {
      puts "RM-Error: DFT setup from TestMAX Manager missing. Please run TestMAX Manager first"
    }
  } else {
    puts "HPC-Info: Skipping DFT insertion entirely since DFT_INSERT_ENABLE=$DFT_INSERT_ENABLE"
  }
  save_block -as ${DESIGN_NAME}/insert_dft
}

####################################
## MV setup : provide a customized MV script	
####################################
## A Tcl script placeholder for your MV setup commands,such as power switch creation and level shifter insertion, etc
## MV_setup file to source HPC MV files
rm_source -file $TCL_MV_SETUP_FILE -optional -print "TCL_MV_SETUP_FILE"
if {$HPC_CORE != ""} {rm_source -file ${HPC_UTILITIES_DIR}/insert_mv.tcl -optional -print "HPC_MV_SETUP_FILE"}

#################################################################################
## Optional library setup files.
#################################################################################

## Adjustment file for modes/corners/scenarios/models to applied to each step (optional)
rm_source -file $TCL_MODE_CORNER_SCENARIO_MODEL_ADJUSTMENT_FILE -optional -print "TCL_MODE_CORNER_SCENARIO_MODEL_ADJUSTMENT_FILE"
if {$HPC_CORE != ""} {rm_source -file ${HPC_UTILITIES_DIR}/uncertainty_transition_adjustment.tcl -print "HPC_MODE_CORNER_SCENARIO_MODEL_ADJUSTMENT_FILE"}

## Library cell purpose file to be applied in each step (optional)
rm_source -file $TCL_LIB_CELL_PURPOSE_FILE -optional -print "TCL_LIB_CELL_PURPOSE_FILE"

##########################################################################################
## Settings
##########################################################################################
if {$MAX_ROUTING_LAYER != ""} {set_ignored_layers -max_routing_layer $MAX_ROUTING_LAYER} else { puts "RM-info: MAX_ROUTING_LAYER not defined, the highest techfile metal layer will be used by default" } 
if {$MIN_ROUTING_LAYER != ""} {set_ignored_layers -min_routing_layer $MIN_ROUTING_LAYER} else { puts "RM-info: MIN_ROUTING_LAYER not defined, the lowest techfile metal layer will be used by default" }

## Non-persistent settings to be applied in each step (optional)
rm_source -file $TCL_USER_NON_PERSISTENT_SCRIPT -optional -print "TCL_USER_NON_PERSISTENT_SCRIPT"
if {$HPC_CORE != ""} {rm_source -file ${HPC_PLUGINS_DIR}/non_persistent_script.tcl -print "HPC_NON_PERSISTENT_SCRIPT"; set CURRENT_PLUGIN_STEP "non_persistent"; source $HPC_USER_OVERRIDES_SCRIPT}

## Multi Vt constraint file to be applied in each step (optional)
rm_source -file $TCL_MULTI_VT_CONSTRAINT_FILE -optional -print "TCL_MULTI_VT_CONSTRAINT_FILE"

#################################################################################
## Load custom HPC options and files.
#################################################################################

## HPC_CORE specific
if {$HPC_CORE != "" } {
  set HPC_STAGE "fast_compile"
  puts "RM-info: HPC_CORE is being set to $HPC_CORE; Loading HPC settings for stage $HPC_STAGE"
  redirect -tee -file ${REPORTS_DIR}/${REPORT_PREFIX}/${DESIGN_NAME}.set_hpc_options {set_hpc_options -core $HPC_CORE -stage $HPC_STAGE -report_only}
  set_hpc_options -core $HPC_CORE -stage $HPC_STAGE
  
  if {[info exists HPC_BOUNDS_SCRIPT] && $HPC_BOUNDS_SCRIPT != ""} {
    rm_source -file $HPC_BOUNDS_SCRIPT -print "HPC_BOUNDS_SCRIPT"
  }
}

puts "RM-info: Checking for propagated clocks"
set currentMode [current_mode]
foreach_in_collection mode [all_modes] {
    current_mode $mode
    if {[regexp true [get_attribute [all_clocks] propagated_clock]]} {
       set clock_tree [remove_from_collection [all_fanout -flat -clock_tree] [all_registers -clock_pins]]
       if { [sizeof_collection $clock_tree] > 0 } {
           puts "HPC-Warning: Propagated clocks found in $CURRENT_STEP ; applying remove_propagated_clock ..."
           remove_propagated_clock [get_pins -hierarchical]
           remove_propagated_clock [get_ports]
           remove_propagated_clock [get_clocks -filter !is_virtual]
       }
    }
}
current_mode $currentMode

####################################
## Pre-fast_compile customizations
####################################
if {$HPC_CORE != ""} {rm_source -file ${HPC_PLUGINS_DIR}/fast_compile_hpc_pre_script.tcl -print "HPC_FAST_COMPILE_PRE_SCRIPT"; set CURRENT_PLUGIN_STEP "fast_compile_hpc_pre"; source $HPC_USER_OVERRIDES_SCRIPT}

redirect -tee -file ${REPORTS_DIR}/${REPORT_PREFIX}/report_app_options.start     {report_app_options -non_default *}
redirect      -file ${REPORTS_DIR}/${REPORT_PREFIX}/report_lib_cell_purpose      {report_lib_cell -objects [get_lib_cells] -column {full_name:80 valid_purposes}}
redirect      -file ${REPORTS_DIR}/${REPORT_PREFIX}/report_activity.driver.start {report_activity -driver}

#################################################################################
## Start compile
## Run compile_fusion -to initial_place before committing the blocks
#################################################################################
save_block -as ${DESIGN_NAME}/pre_compile

#################################################################################
## compile_fusion -to initial_map
#################################################################################
puts "RM-info: Running compile_fusion -to initial_map"
compile_fusion -to initial_map
save_block -as ${DESIGN_NAME}/initial_map

#################################################################################
## compile_fusion -from logic_opto -to logic_opto
#################################################################################
## Mark clock network as ideal
puts "RM-info: Marking clock network as ideal"
set currentMode [current_mode]
foreach_in_collection mode [all_modes] {
    current_mode $mode
    set clock_tree [remove_from_collection [all_fanout -flat -clock_tree] [all_registers -clock_pins]]
    if { [sizeof_collection $clock_tree] > 0 } {
        set_ideal_network $clock_tree
    }
}
current_mode $currentMode

puts "RM-info: Running compile_fusion -from logic_opto -to logic_opto"
compile_fusion -from logic_opto -to logic_opto

connect_pg_net -automatic

save_block -as ${DESIGN_NAME}/logic_opto

##########################################################################################
## compile_fusion -from initial_place -to initial_place  
##########################################################################################
	 
## Clock NDR modeling at compile_fusion
# mark_clock_trees makes compile_fusion recognize them to model the congestion impact when trial CTS is not run.
puts "RM-info: Running mark_clock_trees -routing_rules to model clock NDR impact during compile_fusion"
mark_clock_trees -routing_rules

if {$HPC_CORE != "" && $DFT_INSERT_ENABLE} {
  rm_source -file $HPC_CONSTRAINTS_POST_DFT -optional -print $HPC_CONSTRAINTS_POST_DFT
}

rm_source -file $TCL_USER_COMPILE_INITIAL_PLACE_PRE_SCRIPT -optional -print "TCL_USER_COMPILE_INITIAL_PLACE_PRE_SCRIPT"
if {$HPC_CORE != ""} {rm_source -file ${HPC_PLUGINS_DIR}/compile_initial_place_pre_script.tcl -optional -print "HPC_COMPILE_INITIAL_PLACE_PRE_SCRIPT"; set CURRENT_PLUGIN_STEP "compile_initial_place_pre"; source $HPC_USER_OVERRIDES_SCRIPT}

puts "RM-info: Running compile_fusion -from initial_place -to initial_place"
compile_fusion -from initial_place -to initial_place
save_block -as ${DESIGN_NAME}/initial_place

## Legalize placement to remove cells overlapping exclusive bounds.
legalize_placement

## Change names
if {$DEFINE_NAME_RULES_OPTIONS != ""} {
  eval define_name_rules verilog $DEFINE_NAME_RULES_OPTIONS
}
redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/report_name_rules.log {report_name_rules}
redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/report_names.log      {report_names -rules verilog}
change_names -rules verilog -hierarchy

####################################
## Post-fast_compile customizations
####################################
if {$HPC_CORE != ""} {
  rm_source -file ${HPC_PLUGINS_DIR}/fast_compile_hpc_post_script.tcl -optional -print "HPC_FAST_COMPILE_POST_SCRIPT"; set CURRENT_PLUGIN_STEP "fast_compile_hpc_post"; source $HPC_USER_OVERRIDES_SCRIPT
  hpc_set_uncertainty_to_signoff
}

save_block

set_svf -off

###########################################################################################
## Report and output
###########################################################################################
if {$REPORT_QOR} {
	set REPORT_STAGE synthesis
	set REPORT_ACTIVE_SCENARIOS $REPORT_FAST_COMPILE_HPC_ACTIVE_SCENARIO_LIST
	if {$REPORT_PARALLEL_SUBMIT_COMMAND != ""} {
		## Generate a file to pass necessary RM variables for running report_qor.tcl to the report_parallel command
		rm_generate_variables_for_report_parallel -work_directory ${REPORTS_DIR}/${REPORT_PREFIX} -file_name rm_tcl_var.tcl

		## Parallel reporting using the report_parallel command (requires a valid REPORT_PARALLEL_SUBMIT_COMMAND)
		report_parallel -work_directory ${REPORTS_DIR}/${REPORT_PREFIX} -submit_command ${REPORT_PARALLEL_SUBMIT_COMMAND} -max_cores ${REPORT_PARALLEL_MAX_CORES} -user_scripts [list "${REPORTS_DIR}/${REPORT_PREFIX}/rm_tcl_var.tcl" "[which report_qor.tcl]"]
	} else {
		## Classic reporting
		rm_source -file report_qor.tcl
	}
}

redirect -tee -file ${REPORTS_DIR}/${REPORT_PREFIX}/run_end.rpt {run_end}
write_qor_data -report_list "performance host_machine report_app_options" -label $REPORT_PREFIX -output $WRITE_QOR_DATA_DIR

report_msg -summary
print_message_info -ids * -summary
echo [date] > fast_compile_hpc

exit 
