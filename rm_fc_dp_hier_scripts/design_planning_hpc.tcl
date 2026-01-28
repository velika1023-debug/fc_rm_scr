##########################################################################################
# Tool: Fusion Compiler 
# Script: design_planning_hpc.tcl
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

set PREVIOUS_STEP $FAST_COMPILE_HPC_BLOCK_NAME
set CURRENT_STEP  $DESIGN_PLANNING_HPC_BLOCK_NAME
set REPORT_PREFIX $CURRENT_STEP
file mkdir ${REPORTS_DIR}/${REPORT_PREFIX}
puts "RM-info: PREVIOUS_STEP = $PREVIOUS_STEP"
puts "RM-info: CURRENT_STEP  = $CURRENT_STEP"
puts "RM-info: REPORT_PREFIX = $REPORT_PREFIX"

redirect -tee -file ${REPORTS_DIR}/${REPORT_PREFIX}/run_start.rpt {run_start}

set_svf ${OUTPUTS_DIR}/${DESIGN_PLANNING_HPC_BLOCK_NAME}.svf

rm_source -file $TCL_PVT_CONFIGURATION_FILE -optional -print "TCL_PVT_CONFIGURATION_FILE"

########################################################################
# Open design
########################################################################
rm_open_design -from_lib      ${WORK_DIR}/${DESIGN_LIBRARY} \
               -block_name    $DESIGN_NAME \
               -from_label    $PREVIOUS_STEP \
               -to_label      $CURRENT_STEP \
	       -dp_block_refs $SUB_BLOCK_REFS

link_block

## Setup distributed processing options
set HOST_OPTIONS ""
if {$DISTRIBUTED} {
   ## Set host options for all blocks.
   set_host_options -name block_script -submit_command $BLOCK_DIST_JOB_COMMAND
   set HOST_OPTIONS "-host_options block_script"

   ## This is an advanced capability which enables custom resourcing for specific blocks.
   ## It is not needed if all blocks have the same resource requirements.  See the
   ## comments embedded for the BLOCK_DIST_JOB_FILE variable definition to setup.
   rm_source -file $BLOCK_DIST_JOB_FILE -optional -print "BLOCK_DIST_JOB_FILE"

   report_host_options
}

## Set active scenarios for the step
if {[info exists DESIGN_PLANNING_HPC_ACTIVE_SCENARIO_LIST] && $DESIGN_PLANNING_HPC_ACTIVE_SCENARIO_LIST != ""} {
	set_scenario_status -active false [get_scenarios -filter active]
	set_scenario_status -active true $DESIGN_PLANNING_HPC_ACTIVE_SCENARIO_LIST
}

## Adjustment file for modes/corners/scenarios/models to applied to each step (optional)
rm_source -file $TCL_MODE_CORNER_SCENARIO_MODEL_ADJUSTMENT_FILE -optional -print "TCL_MODE_CORNER_SCENARIO_MODEL_ADJUSTMENT_FILE"
if {$HPC_CORE != ""} {rm_source -file ${HPC_UTILITIES_DIR}/uncertainty_transition_adjustment.tcl -print "HPC_MODE_CORNER_SCENARIO_MODEL_ADJUSTMENT_FILE"}

rm_source -file $TCL_LIB_CELL_PURPOSE_FILE -optional -print "TCL_LIB_CELL_PURPOSE_FILE"

## Non-persistent settings to be applied in each step (optional)
rm_source -file $TCL_USER_NON_PERSISTENT_SCRIPT -optional -print "TCL_USER_NON_PERSISTENT_SCRIPT"
if {$HPC_CORE != ""} {rm_source -file ${HPC_PLUGINS_DIR}/non_persistent_script.tcl -print "HPC_NON_PERSISTENT_SCRIPT"; set CURRENT_PLUGIN_STEP "non_persistent"; source $HPC_USER_OVERRIDES_SCRIPT}

########################################################################
## Pre-Design_planning User Customizations
########################################################################
if {$HPC_CORE != ""} {rm_source -file ${HPC_PLUGINS_DIR}/design_planning_hpc_pre_script.tcl -print "HPC_DESIGN_PLANNING_PRE_SCRIPT"; set CURRENT_PLUGIN_STEP "design_planning_hpc_pre"; source $HPC_USER_OVERRIDES_SCRIPT}

########################################################################
## Insert MSCTS H-Tree
########################################################################
if {$CTS_STYLE == "MSCTS"} {
  rm_source -file $TCL_REGULAR_MSCTS_FILE -print "TCL_REGULAR_MSCTS_FILE"
}

########################################################################
## Split Constraints
########################################################################
##  create PD-VA map file
puts "RM-info: Creating power domain/voltage area map file"
rm_create_power_domain_map -map ${REPORTS_DIR}/${REPORT_PREFIX}/$DP_VA_MAP_FILE

if {$DP_HIGH_CAPACITY_MODE != "true"} {
  file delete -force split

  # Derive block instances from block references if not already defined.
  set SUB_BLOCK_INSTS ""
  foreach ref "$SUB_BLOCK_REFS" {
     set SUB_BLOCK_INSTS "$SUB_BLOCK_INSTS [get_object_name [get_cells -hier -filter ref_name==$ref]]"
  }

  ## Load any split_constraints setup (i.e. app_options, etc.)
  rm_source -file $TCL_SPLIT_CONSTRAINTS_SETUP_FILE -optional -print "TCL_SPLIT_CONSTRAINTS_SETUP_FILE"

  set_budget_options -add_blocks $SUB_BLOCK_INSTS

  if {$DEF_SCAN_FILE == ""} {
    puts "RM-Info : Splitting constraints: split_constraints -force -nosplit"
    split_constraints -force -nosplit
  } else {
    puts "RM-Info : Splitting constraints: split_constraints -force -nosplit -include_scandef true"
    split_constraints -force -nosplit -include_scandef true
  }

  ########################################################################
  ## Pre-Commit_Block User Customizations
  ########################################################################
  rm_source -optional -file $TCL_USER_COMMIT_BLOCK_PRE_SCRIPT -print "TCL_USER_COMMIT_BLOCK_PRE_SCRIPT"
  if {$HPC_CORE != ""} {rm_source -file ${HPC_PLUGINS_DIR}/commit_block_pre_script.tcl -print "HPC_COMMIT_BLOCK_PRE_SCRIPT"; set CURRENT_PLUGIN_STEP "commit_block_pre"; source $HPC_USER_OVERRIDES_SCRIPT}

  # reset upf after split_constraints, splitted upf will be loaded by each block hierarchically
  reset_upf

  if {[info exists SUB_BB_BLOCK_REFS] && $SUB_BB_BLOCK_REFS != ""} {
     set SUB_BB_BLOCK_INSTS ""
     foreach ref $SUB_BB_BLOCK_REFS {
       set SUB_BB_BLOCK_INSTS "$SUB_BB_BLOCK_INSTS [get_object_name [get_cells -hier -filter ref_name==$ref]]"
     }
     set cb [current_block]
     foreach bb $SUB_BB_BLOCK_INSTS { create_blackbox $bb }
     foreach bb $SUB_BB_BLOCK_REFS {
        # If BB UPF provided, load it
        if {[info exists SUB_BB_BLOCKS(${bb},upf)] && [file exists $SUB_BB_BLOCKS(${bb},upf)]} {
           current_block ${bb}.design
           load_upf $SUB_BB_BLOCKS(${bb},upf)
           commit_upf
           save_upf -for_empty_blackbox ./split/$bb/top.upf
           current_block $DESIGN_NAME
        }
        # if BB timing exists put it in split directory as well
        if {[info exists SUB_BB_BLOCKS(${bb},timing)] && [file exists $SUB_BB_BLOCKS(${bb},timing)]} {
           exec cat $SUB_BB_BLOCKS(${bb},timing) >> ./split/$bb/top.tcl
        }
     }
  }
}

########################################################################
## Commit blocks
########################################################################

## Removes child block references when this task is being rerun.
set reference_libs [get_attribute [current_lib] ref_libs]
foreach ref_lib $reference_libs {
  set ref_lib_tail [file tail $ref_lib]
  foreach BLOCK_REF $SUB_BLOCK_REFS {
    set BLOCK_REF_NLIB "${BLOCK_REF}.nlib"
    if {$ref_lib_tail == $BLOCK_REF_NLIB} {
      puts "RM-info : Removing [format %-25s $ref_lib] as a reference of [get_object_name [current_lib]]"
      set_ref_libs -remove [file normalize $ref_lib]
    }
  }
}

##### create block libs
set backup_suffix "backup_[exec date +%y%m%d_%H%M]" ;
foreach ref $SUB_BLOCK_REFS {
  set target_design_lib ${WORK_DIR}/${ref}${LIBRARY_SUFFIX} ;
  puts "RM-info: Creating ${target_design_lib}" ;
  if { [file exists $target_design_lib] } {
    file rename -force -- $target_design_lib ${target_design_lib}_${backup_suffix} ;
  }
  copy_lib -to_lib $target_design_lib -no_designs ;
  set_attribute -object [get_lib ${target_design_lib}] -name use_hier_ref_libs -value true ;
}

save_lib -all

# Create blackboxes
foreach ref $SUB_BB_BLOCK_REFS {
   # Create the black boxes, and set the area if defined, otherwise
   set inst [index_collection [filter_collection [get_cells $SUB_BLOCK_INSTS] ref_name==$ref] 0]
   puts "RM-info : Creating blackbox $ref into library ${ref}${LIBRARY_SUFFIX}"
   if {[info exists SUB_BB_BLOCKS($ref,area)]} {
     create_blackbox -library ${ref}${LIBRARY_SUFFIX} -target_boundary_area $SUB_BB_BLOCKS($ref,area) $inst
   } elseif {[info exists SUB_BB_BLOCKS($ref,boundary)]} {
     create_blackbox -library ${ref}${LIBRARY_SUFFIX} -boundary $SUB_BB_BLOCKS($ref,boundary) $inst
   } else {
     puts "RM-error : Black boxes are defined as $SUB_BB_BLOCK_REFS, but have no area or boundary, assign an area in setup.tcl"
     error "Stopped due to above RM-error"
   }
}

## Commit all non-black box blocks
foreach ref $SUB_BLOCK_REFS {
  if {[lsearch $SUB_BB_BLOCK_REFS $ref] < 0} {
    puts "RM-info : Committing block $ref into library ${ref}${LIBRARY_SUFFIX}"
    commit_block -library ${ref}${LIBRARY_SUFFIX} $ref
    save_block -as ${DESIGN_NAME}/${DESIGN_PLANNING_HPC_BLOCK_NAME}_commit_block
  }
}

## Get block names for references defined by SUB_BLOCK_REFS.  This list is used in some hier DP commands.
set child_blocks [ list ]
foreach block $SUB_BLOCK_REFS {lappend child_blocks [get_object_name [get_blocks -hier -filter block_name==$block]]}
set all_blocks "$child_blocks [get_object_name [current_block]]"

## Add child block reference to parent block
foreach inst $SUB_BLOCK_INSTS {
  # Add a reference to any child blocks
  set ref_lib_name        [get_attribute [get_cells $inst] ref_lib_name]
  set parent_ref_lib_name [get_attribute [get_cells $inst] parent_block.lib_name]
  # Check to see if ref lib already exists in the case of MIB
  if {[lsearch [get_attribute [get_libs $parent_ref_lib_name] ref_libs] "./${ref_lib_name}"] < 0} {
    puts "RM-info : Adding ./${ref_lib_name} as a reference of ${parent_ref_lib_name}"
    set_ref_libs -library $parent_ref_lib_name -add ./${ref_lib_name}
  }
}

########################################################################
## Loading the constraints into the committed blocks
########################################################################
if {$DP_HIGH_CAPACITY_MODE != "true"} {
  ## Load block constraints 
  if {$CONSTRAINT_MAPPING_FILE != ""} {
     set_constraint_mapping_file $CONSTRAINT_MAPPING_FILE
  } else {
     set default_mapfile [file normalize ./split/mapfile]
     puts "RM-warning : CONSTRAINT_MAPPING_FILE was not set, setting the constraint mapping file to the default $default_mapfile"
     set_constraint_mapping_file $default_mapfile
  }
  report_constraint_mapping_file

  eval load_block_constraints -type SDC -type UPF -type CLKNET -blocks [get_blocks ${all_blocks}] ${HOST_OPTIONS}
}

## Push-down VA, if already defined
if {[file exists ${REPORTS_DIR}/${REPORT_PREFIX}/$DP_VA_MAP_FILE] } {
  foreach hier_inst_name $SUB_BLOCK_INSTS {
    puts "RM-info: Pushing down VA for $hier_inst_name ..."
    set hier_inst [get_cells $hier_inst_name]
    rm_push_down_voltage_areas -cell $hier_inst -map ${REPORTS_DIR}/${REPORT_PREFIX}/$DP_VA_MAP_FILE
  }
}

## Push-down user attr, if already defined.
set cur_compile_fusion_step [get_attribute -quiet [current_block] compile_fusion_step]
if {$cur_compile_fusion_step != ""} {
  foreach inst $SUB_BLOCK_INSTS {
    set_working_design -push $inst
    set_attribute [current_block] compile_fusion_step $cur_compile_fusion_step
    set_working_design -pop -level 0
  }
}
if {$HPC_CORE != ""} {
  rm_source -file ${HPC_UTILITIES_DIR}/dp.pushdown.tcl -optional -print "HPC_PUSHDOWN_OBJECTS_POST"
  ## Create initial abstracts for HPC flow when abstract flow is enabled.
  ## - Note that this is done in the init_compile task for the SoC flow.
  if {$BOTTOM_BLOCK_VIEW == "abstract"} {
    puts "RM-info : Running create_abstract -timing_level $BLOCK_ABSTRACT_TIMING_LEVEL -blocks \"$child_blocks\" $HOST_OPTIONS"
    set create_abstract_cmd "create_abstract -timing_level $BLOCK_ABSTRACT_TIMING_LEVEL -blocks [get_blocks $child_blocks] $HOST_OPTIONS"
    eval ${create_abstract_cmd}
    ## Get block names for references defined by SUB_BLOCK_REFS.  This list is used in some hier DP commands.
    set child_blocks [ list ]
    foreach block $SUB_BLOCK_REFS {lappend child_blocks [get_object_name [get_blocks -hier -filter block_name==$block]]}
    set all_blocks "$child_blocks [get_object_name [current_block]]"
  }
}

########################################################################
## Post-Commit_Block User Customizations
########################################################################
rm_source -optional -file $TCL_USER_COMMIT_BLOCK_POST_SCRIPT -print TCL_USER_COMMIT_BLOCK_POST_SCRIPT ;
if {$HPC_CORE != ""} {rm_source -file ${HPC_PLUGINS_DIR}/commit_block_post_script.tcl -optional -print "HPC_COMMIT_BLOCK_POST_SCRIPT"; set CURRENT_PLUGIN_STEP "commit_block_post"; source $HPC_USER_OVERRIDES_SCRIPT}

save_lib -all
####################################
## Pre-place_pins User Customizations
####################################
rm_source -file $TCL_USER_PLACE_PINS_PRE_SCRIPT -optional -print "TCL_USER_PLACE_PINS_PRE_SCRIPT"
if {$HPC_CORE != ""} {rm_source -file ${HPC_PLUGINS_DIR}/place_pins_pre_script.tcl -optional -print "HPC_PLACE_PINS_PRE_SCRIPT"; set CURRENT_PLUGIN_STEP "place_pins_pre"; source $HPC_USER_OVERRIDES_SCRIPT}

########################################################################
## Set pin constraints if not PLACEMENT_PIN_CONSTRAINT_AWARE.
##   TCL_PIN_CONSTRAINT_FILE   : This file contains all the TCL set_*_pin_constraints.
##   CUSTOM_PIN_CONSTRAINT_FILE: This file contains the pin constraints in pin constraint format, not TCL.
##   not TCL.
## Note: Feedthroughs are not enabled by default; Enable feedthroughs either through the Tcl pin constraints command or through the pin constraints file
################################################################################
if {!$PLACEMENT_PIN_CONSTRAINT_AWARE} {
   rm_source -optional -file $TCL_PIN_CONSTRAINT_FILE -print TCL_PIN_CONSTRAINT_FILE ;

   if {[file exists [which $CUSTOM_PIN_CONSTRAINT_FILE]]} {
     read_pin_constraints -file_name $CUSTOM_PIN_CONSTRAINT_FILE ;
   }
}

################################################################################
## If incremental pin constraints exist and incremental mode is enabled, load them
################################################################################
if {$USE_INCREMENTAL_DATA && [file exists $OUTPUTS_DIR/preferred_pin_locations.tcl]} {
   read_pin_constraints -file_name $OUTPUTS_DIR/preferred_pin_locations.tcl
}

################################################################################
# Enable timing driven pin placement
################################################################################
if {$TIMING_PIN_PLACEMENT} {
   rm_source -file $TCL_TIMING_ESTIMATION_SETUP_FILE -optional -print "TCL_TIMING_ESTIMATION_SETUP_FILE"
  
   if {$SUB_BB_BLOCK_REFS != ""} {
      if {$BOTTOM_BLOCK_VIEW == "abstract"} {
         ## Create timing estimation abstracts for non black boxes at lowest hierachy levels.
         set non_bb_blocks $SUB_BLOCK_REFS
         foreach bb $SUB_BB_BLOCK_REFS {
            set idx [lsearch -exact $non_bb_blocks $bb]
            set non_bb_blocks [lreplace $non_bb_blocks $idx $idx]
         }
         set non_bb_insts ""
         foreach ref $non_bb_blocks {
            set non_bb_insts "$non_bb_insts [get_object_name [get_cells -hier -filter ref_name==$ref]]"
         }
         set non_bb_for_abs [lsort -unique [get_attribute -objects [filter_collection [get_cells $non_bb_insts] "!has_child_physical_hierarchy"] -name ref_name]]
      
         set CMD_OPTIONS "-estimate_timing -timing_level $BLOCK_ABSTRACT_TIMING_LEVEL -blocks [list $non_bb_for_abs] $HOST_OPTIONS"
         puts "RM-info : Running create_abstract $CMD_OPTIONS"
         eval create_abstract $CMD_OPTIONS
      }
      
      ## Load constraints and create abstracts for black boxes.
      set CMD_OPTIONS "-blocks [list $SUB_BB_BLOCK_REFS] -type SDC $HOST_OPTIONS"
      puts "RM-info : Running load_block_constraints $CMD_OPTIONS"
      eval load_block_constraints $CMD_OPTIONS
      
      set CMD_OPTIONS "-timing_level $BLOCK_ABSTRACT_TIMING_LEVEL -blocks [list $SUB_BB_BLOCK_REFS] $HOST_OPTIONS"
      puts "RM-info : Running create_abstract $CMD_OPTIONS"
      eval create_abstract $CMD_OPTIONS
      
   } elseif {$SUB_BLOCK_REFS != ""} {
      if {$BOTTOM_BLOCK_VIEW == "abstract"} {
         puts "RM-info : Running create_abstract -estimate_timing -timing_level $BLOCK_ABSTRACT_TIMING_LEVEL -blocks \"$child_blocks\" $HOST_OPTIONS"
         eval create_abstract -estimate_timing -timing_level $BLOCK_ABSTRACT_TIMING_LEVEL -blocks [get_blocks $child_blocks] $HOST_OPTIONS
      }
   }
   ## Enable timing driven global routing
   set_app_options -as_user_default -list {route.global.timing_driven true}
}

####################################
## Check Design: Pre-Pin Placement
####################################
if {$CHECK_DESIGN} { 
   redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/check_design.pre_pin_placement \
    {check_design -ems_database $REPORTS_DIR/$REPORT_PREFIX/check_design.dp_pre_pin_placement.ems -checks dp_pre_pin_placement -log_file $REPORTS_DIR/$REPORT_PREFIX/check_design.dp_pre_pin_placement.log}
}

if [sizeof_collection [get_cells -quiet -hierarchical -filter "is_multiply_instantiated_block"]] { 
   check_mib_alignment
}

####################################
## Place top-level pins
####################################
## Perform pin placement when both conditions below are met:
## 1) Pin placement is enabled for this task 
## 2) User wants to run even though pin placement was detected in input DEF/TCL
if {!([get_attribute [current_block] top_pin_placement] == "1") || $PLACE_PINS_SELF != "none"} {
  if {($PLACE_PINS_SELF == "place_pins")} {
    place_pins -self
  } elseif {($PLACE_PINS_SELF == "both")} {
    if {[get_attribute [current_block] top_pin_placement_export] != ""} {
      rm_source -file [get_attribute [current_block] top_pin_placement_export]
      place_pins -self -legalize
    } else {
      puts "RM-warning : Running full top-level pin placement as no pin export file found."
      place_pins -self
    }
  }
}

####################################
## Place block pins
####################################
# Note1: 
# If you need to re-run place_pins, it is recommended that you first remove previously created 
# feedthroughs (i.e. run remove_feedthroughs before re-running place_pins).
# If you do not want to disrupt your current pin placement, you can either set the physical status 
# of your block pins to fixed using the set_attribute command like so:
#    icc2_shell> set_attribute [get_terminals -of_objects [get_pins block/A]] physical_status fixed)
# Or you can assign pins for selected nets using place_pins -nets ...; 
# When the "-nets ..." option is used, the place_pins command will place pins only for the specified nets. 
# See the remove_feedthroughs and place_pins man pages for details.

# Note2: Congestion aware block pin assignment
# Optional pin assigment sequence when there is serious congestion around block boundary.
# route_global -floorplan true -virtual_flat top_and_interface_routing_only ;
# place_pin -use_existing_routing ;

## Block pin assignment.
place_pins

################################################################################
# Dump pin constraints for re-use later in an incremental build
################################################################################
write_pin_constraints \
   -file_name $OUTPUTS_DIR/preferred_pin_locations.tcl \
   -physical_pin_constraint {side | offset | layer} \
   -from_existing_pins

################################################################################
## Verfiy Pin assignment results
## If errors are found they will be stored in an .err file and can be browsed
## with the integrated error browser.
################################################################################
switch $FLOORPLAN_STYLE {
   channel {redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/check_pin_placement.${FLOORPLAN_STYLE}.rpt {check_pin_placement -alignment true -pre_route true \
            -sides true -stacking true -pin_spacing true -layers true}}
   abutted {redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/check_pin_placement.${FLOORPLAN_STYLE}.rpt {check_pin_placement -pre_route true -sides true \
            -stacking true -pin_spacing true -layers true -single_pin all -synthesized_pins true}}
}

################################################################################
## Generate a pin placement report to assess pin placement
################################################################################
redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/report_feedthrough.rpt   {report_feedthroughs -reporting_style net_based}
redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/report_pin_placement.rpt {report_pin_placement}

## check_mv_design -erc_mode and -power_connectivity
redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/check_mv_design.erc_mode {check_mv_design -erc_mode}
redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/check_mv_design.power_connectivity {check_mv_design -power_connectivity}

if {($PLACE_PINS_SELF == "place_pins" || $PLACE_PINS_SELF == "both") && (!([get_attribute [current_block] top_pin_placement] == "1") || $PLACE_PINS_SELF != "none")} {
   # Write top-level port constraint file based on actual port locations.
   write_pin_constraints -self \
      -file_name $OUTPUTS_DIR/preferred_port_locations.tcl \
      -physical_pin_constraint {side | offset | layer} \
      -from_existing_pins

   # Verify Top-level Port Placement Results
   redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/check_pin_placement.rpt            {check_pin_placement -self -pre_route true -pin_spacing true -sides true -layers true -stacking true}
   redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/check_pin_placement.pin_detour.rpt {check_pin_placement -layers true -sides true -off_edge true -pin_direction true -single_pin all -wire_track true -pin_detour true -detour_tolerance 1.2 }

   # Generate Top-level Port Placement Report
   redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/report_pin_placement.self.rpt {report_pin_placement -self}
}
  
## Post pin placement node specific file.
## - Typical uses are periphery routing blockages, port diode insertion, etc.
rm_source -file $SIDEFILE_PLACE_PINS -optional -print "SIDEFILE_PLACE_PINS"

####################################
## Post-place_pins customizations
####################################
rm_source -file $TCL_USER_PLACE_PINS_POST_SCRIPT -optional -print "TCL_USER_PLACE_PINS_POST_SCRIPT"
if {$HPC_CORE != ""} {rm_source -file ${HPC_PLUGINS_DIR}/place_pins_post_script.tcl -print "HPC_PLACE_PINS_POST_SCRIPT"; set CURRENT_PLUGIN_STEP "place_pins_post"; source $HPC_USER_OVERRIDES_SCRIPT}

save_block -as ${DESIGN_NAME}/${DESIGN_PLANNING_HPC_BLOCK_NAME}_pins_placed
save_lib -all
####################################
## Pre-budgeting customizations
####################################
rm_source -file $TCL_USER_BUDGETING_PRE_SCRIPT -optional -print "TCL_USER_BUDGETING_PRE_SCRIPT"
if {$HPC_CORE != ""} {rm_source -file ${HPC_PLUGINS_DIR}/budgeting_pre_script.tcl -optional -print "HPC_BUDGETING_PRE_SCRIPT"; set CURRENT_PLUGIN_STEP "budgeting_pre"; source $HPC_USER_OVERRIDES_SCRIPT}

rm_source -file $TCL_TIMING_ESTIMATION_SETUP_FILE -optional -print "TCL_TIMING_ESTIMATION_SETUP_FILE"

################################################################################
## Create estimate_timing abstracts for blocks and run timing estimation.
################################################################################
if {$SUB_BLOCK_REFS != ""} {
   if {$BOTTOM_BLOCK_VIEW == "abstract"} {
      ####################################
      ## Check Design: Pre-Pre Timing
      ####################################
      if {$CHECK_DESIGN} { 
         redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/check_design.pre_create_timing_abstract \
          {check_design -ems_database $REPORTS_DIR/$REPORT_PREFIX/check_design.dp_pre_create_timing_abstract.ems -checks dp_pre_create_timing_abstract -log_file $REPORTS_DIR/$REPORT_PREFIX/check_design.dp_pre_create_timing_abstract.log}
      }
      ## Create abstracts to support estimate_timing.  
      puts "RM-info : Running create_abstract -estimate_timing -timing_level $BLOCK_ABSTRACT_TIMING_LEVEL -blocks \"$child_blocks\" $HOST_OPTIONS"
      eval create_abstract -estimate_timing -timing_level $BLOCK_ABSTRACT_TIMING_LEVEL -blocks [get_blocks $child_blocks] $HOST_OPTIONS
   }
}

####################################
# Check Design: Pre-Timing Estimation
####################################
if {$CHECK_DESIGN} { 
   redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/check_design.pre_timing_estimation \
    {check_design -ems_database $REPORTS_DIR/$REPORT_PREFIX/check_design.dp_pre_timing_estimation.ems -checks dp_pre_timing_estimation -log_file $REPORTS_DIR/$REPORT_PREFIX/check_design.dp_pre_timing_estimation.log}
}
      
## Run timing estimation on the entire top design to ensure quality 
eval estimate_timing $HOST_OPTIONS

###############################################################################
# Generate Post Timing Estimation Reports 
###############################################################################
redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/${DESIGN_NAME}.post_estimated_timing.rpt     {report_timing -corner estimated_corner -mode [all_modes]}
redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/${DESIGN_NAME}.post_estimated_timing.qor     {report_qor    -corner estimated_corner}
redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/${DESIGN_NAME}.post_estimated_timing.qor.sum {report_qor    -summary}

## Ensure that timing derates were loaded during CTP for valid report.
if {[file exists [which $CTP_TIMING_DERATE_SCRIPT]]} {
  redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/${DESIGN_NAME}.post_estimated_timing_clock_trunk.qor {report_clock_trunk_qor -clock $CTP_CLOCKS}
}

################################################################################
# Load budgeting user setup file if defined
################################################################################
rm_source -file $TCL_BUDGETING_SETUP_FILE -optional -print "TCL_BUDGETING_SETUP_FILE"
if {$HPC_CORE != ""} {rm_source -file ${HPC_PLUGINS_DIR}/budget_setup.tcl -print "HPC_BUDGETING_SETUP_FILE"; set CURRENT_PLUGIN_STEP "budget_setup"; source $HPC_USER_OVERRIDES_SCRIPT}

####################################
# Check Design: Pre-Budgets
####################################
if {$CHECK_DESIGN} { 
   redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/check_design.pre_budgeting \
    {check_design -ems_database $REPORTS_DIR/$REPORT_PREFIX/check_design.dp_pre_budgeting.ems -checks dp_pre_budgeting -log_file $REPORTS_DIR/$REPORT_PREFIX/check_design.dp_pre_budgeting.log}
}

################################################################################
# Budgeting
################################################################################
# Derive block instances from block references if not already defined.
set SUB_BLOCK_INSTS ""
foreach ref "$SUB_BLOCK_REFS" {
   set SUB_BLOCK_INSTS "$SUB_BLOCK_INSTS [get_object_name [get_cells -hier -filter ref_name==$ref]]"
}

## Setup blocks to be budgeted.
set_budget_options -add_blocks $SUB_BLOCK_INSTS

## Compute the budgets.
## - Note that the default COMPUTE_BUDGET_CONSTRAINTS_OPTIONS setting defines "-latency_target actual".  
##   If clock_trunk_planning was run you will need to edit to "estimated".
set compute_budget_constraints_cmd "compute_budget_constraints $COMPUTE_BUDGET_CONSTRAINTS_OPTIONS"
puts "RM-info : Running: $compute_budget_constraints_cmd"
eval $compute_budget_constraints_cmd

################################################################################
# Load boundary budgeting constraint file if defined
# - Manual fine tuning of budgets.
################################################################################
rm_source -file $TCL_BOUNDARY_BUDGETING_CONSTRAINTS_FILE -optional -print "TCL_BOUNDARY_BUDGETING_CONSTRAINTS_FILE"
if {$HPC_CORE != ""} {rm_source -file ${HPC_PLUGINS_DIR}/boundary_budget_constraints_file.tcl -print "HPC_BOUNDARY_BUDGETING_CONSTRAINTS_FILE"; set CURRENT_PLUGIN_STEP "boundary_budget_constraints"; source $HPC_USER_OVERRIDES_SCRIPT}

###############################################################################
# Write Out Budgets
################################################################################
if {[file exists ./block_budgets]} {
  file rename ./block_budgets ./block_budgets_bak_[exec date +%y%m%d_%H%M%S] ;
}

save_block -as ${DESIGN_NAME}/${DESIGN_PLANNING_HPC_BLOCK_NAME}_pre_write_budgets
write_budgets -output block_budgets -force -nosplit

redirect -file ${REPORTS_DIR}/${REPORT_PREFIX}/report_budget.latency {report_budget -latency} ;
report_budget -html_dir ${REPORTS_DIR}/${REPORT_PREFIX}/${DESIGN_NAME}.budget.html ;

####################################
## Post write budget customizations
####################################
if {$HPC_CORE != ""} {rm_source -file ${HPC_PLUGINS_DIR}/write_budget_post_script.tcl -optional -print "HPC_WRITE_BUDGET_POST_SCRIPT"; set CURRENT_PLUGIN_STEP "write_budget_post"; source $HPC_USER_OVERRIDES_SCRIPT}

################################################################################
# Write Out Budget Constraints
################################################################################
write_script -include budget -force -output ${REPORTS_DIR}/${REPORT_PREFIX}/${DESIGN_NAME}.budget_constraints

################################################################################
# Load Block Budget Constraints
################################################################################

## Save required prior to run_block_script.
save_lib -all

## Added the -force due to unsaved bottom-up library edits.  Fix to Jira 33522588 should address.
set save_DESIGN_NAME $DESIGN_NAME
set load_block_budgets_script "./rm_fc_dp_hier_scripts/load_block_budgets.tcl"

eval run_block_script -script $load_block_budgets_script \
     -blocks [list "${SUB_BLOCK_REFS}"] \
     -work_dir ./work_dir/load_block_budgets $HOST_OPTIONS \
     -force
set DESIGN_NAME $save_DESIGN_NAME

## Re-create abstracts as they become out of sync after budget loading.
## - Abstracts can be used to support analysis at the end of DP.
if {$BOTTOM_BLOCK_VIEW == "abstract"} {
   puts "RM-info : Running create_abstract -timing_level $BLOCK_ABSTRACT_TIMING_LEVEL -blocks \"$child_blocks\" $HOST_OPTIONS"
   eval create_abstract -timing_level $BLOCK_ABSTRACT_TIMING_LEVEL -blocks [get_blocks $child_blocks] $HOST_OPTIONS
}

####################################
## Post-timing_budgeting User Customizations
####################################
rm_source -file $TCL_USER_BUDGETING_POST_SCRIPT -optional -print "TCL_USER_BUDGETING_POST_SCRIPT"
if {$HPC_CORE != ""} {rm_source -file ${HPC_PLUGINS_DIR}/budgeting_post_script.tcl -optional -print "HPC_BUDGETING_POST_SCRIPT"; set CURRENT_PLUGIN_STEP "budgeting_post"; source $HPC_USER_OVERRIDES_SCRIPT}

save_lib -all

########################################################################
## Post-Design_planning User Customizations
########################################################################
if {$HPC_CORE != ""} {
  rm_source -file ${HPC_PLUGINS_DIR}/design_planning_hpc_post_script.tcl -optional -print "HPC_DESIGN_PLANNING_POST_SCRIPT"; set CURRENT_PLUGIN_STEP "design_planning_hpc_post"; source $HPC_USER_OVERRIDES_SCRIPT
  hpc_set_uncertainty_to_signoff
}

########################################################################
## Post design planning cleanup
########################################################################

## Remove estimated corner from top-level.
if {[llength [get_corners estimated_corner -quiet]] != 0} {
  remove_corners estimated_corner
}

## Remove constraint mapping file.
set_constraint_mapping_file -reset
    
## Set editablity false for all blocks
set_editability -value false -blocks [get_block -hier]
report_editability -blocks [get_block -hier]

########################################################################
## Finalize step
########################################################################
save_lib -all

set_svf -off

########################################################################
## H-Tree Reporting
########################################################################
if {$CTS_STYLE == "MSCTS"} {
  if {$HPC_CORE != ""} {rm_source -file ${HPC_UTILITIES_DIR}/report_htree.tcl -print "HPC_REPORT_HTREE"}
}

###########################################################################################
## Report and output
###########################################################################################
if {$REPORT_QOR} {
	set REPORT_STAGE synthesis
	set REPORT_ACTIVE_SCENARIOS $REPORT_DESIGN_PLANNING_HPC_ACTIVE_SCENARIO_LIST
	if {$REPORT_PARALLEL_SUBMIT_COMMAND != ""} {
		## Generate a file to pass necessary RM variables for running report_qor.tcl to the report_parallel command
		rm_generate_variables_for_report_parallel -work_directory ${REPORTS_DIR}/${REPORT_PREFIX} -file_name rm_tcl_var.tcl

		## Parallel reporting using the report_parallel command (requires a valid REPORT_PARALLEL_SUBMIT_COMMAND)
		report_parallel -work_directory ${REPORTS_DIR}/${REPORT_PREFIX} -submit_command $REPORT_PARALLEL_SUBMIT_COMMAND -max_cores $REPORT_PARALLEL_MAX_CORES -user_scripts [list "${REPORTS_DIR}/${REPORT_PREFIX}/rm_tcl_var.tcl" "[which report_qor.tcl]"]
	} else {
		## Classic reporting
		rm_source -file report_qor.tcl
	}
}

redirect -tee -file ${REPORTS_DIR}/${REPORT_PREFIX}/run_end.rpt {run_end}
write_qor_data -report_list "performance host_machine report_app_options" -label $REPORT_PREFIX -output $WRITE_QOR_DATA_DIR

report_msg -summary
print_message_info -ids * -summary
echo [date] > design_planning_hpc

exit

