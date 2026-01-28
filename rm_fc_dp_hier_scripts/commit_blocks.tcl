##########################################################################################
# Tool: Fusion Compiler 
# Script: commit_blocks.tcl
# Version: V-2023.12-SP4
# Copyright (C) 2014-2024 Synopsys, Inc. All rights reserved.
##########################################################################################

source ./rm_utilities/procs_global.tcl 
source ./rm_utilities/procs_fc.tcl 
rm_source -file ./rm_setup/design_setup.tcl
rm_source -file ./rm_setup/fc_dp_setup.tcl
rm_source -file ./rm_setup/header_fc_dp.tcl
if {[file exists [which config_setup.tcl]]} {
	rm_source -file config_setup.tcl -after_file technology_override.tcl
} else {
	rm_source -file sidefile_setup.tcl -after_file technology_override.tcl
}

set PREVIOUS_STEP $INIT_DP_BLOCK_NAME
set CURRENT_STEP  $COMMIT_BLOCK_BLOCK_NAME
set REPORT_PREFIX ${CURRENT_STEP}
file mkdir ${REPORTS_DIR}/${REPORT_PREFIX}
puts "RM-info: PREVIOUS_STEP = $PREVIOUS_STEP"
puts "RM-info: CURRENT_STEP  = $CURRENT_STEP"
puts "RM-info: REPORT_PREFIX = $REPORT_PREFIX"

redirect -tee -file ${REPORTS_DIR}/${REPORT_PREFIX}/run_start.rpt {run_start}

rm_source -file $TCL_PVT_CONFIGURATION_FILE -optional -print "TCL_PVT_CONFIGURATION_FILE"

########################################################################
## Open design
########################################################################
if {$NETLIST2GDS_FLOW} {
  if {$DP_HIGH_CAPACITY_MODE} {
    set DESIGN_VIEW "outline"
  } else {
    set DESIGN_VIEW "design"
  }
} else {
  set DESIGN_VIEW "design"
}

rm_open_design -from_lib      ${WORK_DIR}/${DESIGN_LIBRARY} \
               -block_name    $DESIGN_NAME \
               -from_label    $PREVIOUS_STEP \
               -to_label      $CURRENT_STEP \
               -view          $DESIGN_VIEW \
	       -dp_block_refs $SUB_BLOCK_REFS

## Setup distributed processing options
set HOST_OPTIONS ""
if {$DISTRIBUTED} {
   ## Set host options for all blocks.
   set_host_options -name block_script -submit_command $BLOCK_DIST_JOB_COMMAND
   set HOST_OPTIONS "-host_options block_script"
   report_host_options
}

## Derive block instances from block references if not already defined.
set SUB_BLOCK_INSTS ""
foreach ref "$SUB_BLOCK_REFS" {
   set SUB_BLOCK_INSTS "$SUB_BLOCK_INSTS [get_object_name [get_cells -hier -filter ref_name==$ref]]"
}

## Non-persistent settings to be applied in each step (optional)
rm_source -file $TCL_USER_NON_PERSISTENT_SCRIPT -optional -print "TCL_USER_NON_PERSISTENT_SCRIPT"
if {$HPC_CORE != ""} {rm_source -file ${HPC_PLUGINS_DIR}/non_persistent_script.tcl -optional -print "HPC_NON_PERSISTENT_SCRIPT"}

########################################################################
## Split Constraints
########################################################################
##  create PD-VA map file
puts "RM-info: Creating power domain/voltage area map file"
rm_create_power_domain_map -map $DP_VA_MAP_FILE

if {$NETLIST2GDS_FLOW && $DP_HIGH_CAPACITY_MODE} {
  ## Split_constraints is run as a separate step for the N2G high capacity flow.
} else {
  file delete -force split

  # Derive block instances from block references if not already defined.
  set SUB_BLOCK_INSTS ""
  foreach ref "$SUB_BLOCK_REFS" {
     set SUB_BLOCK_INSTS "$SUB_BLOCK_INSTS [get_object_name [get_cells -hier -filter ref_name==$ref]]"
  }

  ## Load any split_constraints setup (i.e. app_options, etc.)
  rm_source -file $TCL_SPLIT_CONSTRAINTS_SETUP_FILE -optional -print "TCL_SPLIT_CONSTRAINTS_SETUP_FILE"

  set_budget_options -add_blocks $SUB_BLOCK_INSTS

  puts "RM-Info : Splitting constraints"
  split_constraints -nosplit

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
## Pre-Commit_Block User Customizations
########################################################################
rm_source -optional -file $TCL_USER_COMMIT_BLOCK_PRE_SCRIPT -print "TCL_USER_COMMIT_BLOCK_PRE_SCRIPT"
if {$HPC_CORE != ""} {rm_source -file ${HPC_PLUGINS_DIR}/commit_block_pre_script.tcl optional -print "HPC_COMMIT_BLOCK_PRE_SCRIPT"}
########################################################################
## Commit blocks
########################################################################

## Removes child block references when this task is being rerun.
set reference_libs [get_attribute [current_lib] ref_libs]
set ref_lib_output "./reference_library_list.txt"
if {[file exists $ref_lib_output]} {
  set fid [ open $ref_lib_output r ]
  set golden_ref_lib_list [ read $fid ]
  close $fid
  foreach lib $reference_libs {
    if {[lsearch $golden_ref_lib_list $lib] < 0} {
      puts "RM-info : Removing $lib as a reference of [get_object_name [current_lib]]"
      set_ref_libs -remove [file normalize $lib]
    }
  }
} else {
  if {[llength $reference_libs] > 0} {
    set fid [ open $ref_lib_output "w" ]
    puts $fid "[get_attribute [current_lib] ref_libs]"
    close $fid
  } else {
    puts "RM-error : No reference libraries were detected."
  }
}

##### create block libs
set backup_suffix "backup_[exec date +%y%m%d_%H%M]" ;
foreach ref ${SUB_BLOCK_REFS} {
  set target_design_lib ${WORK_DIR}/${ref}${LIBRARY_SUFFIX} ;
  puts "RM-info: Creating ${target_design_lib}" ;
  if { [file exists $target_design_lib] } {
    file rename -force -- ${target_design_lib} ${target_design_lib}_${backup_suffix} ;
  }
  copy_lib -to_lib ${target_design_lib} -no_designs ;
  set_attribute -object [get_lib ${target_design_lib}] -name use_hier_ref_libs -value true ;
}

save_lib -all

# Create blackboxes
foreach ref ${SUB_BB_BLOCK_REFS} {
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
foreach ref ${SUB_BLOCK_REFS} {
  if {[lsearch $SUB_BB_BLOCK_REFS $ref] < 0} {
    puts "RM-info : Committing block $ref into library ${ref}${LIBRARY_SUFFIX}"
    commit_block -library ${ref}${LIBRARY_SUFFIX} $ref
  }
}

## Get block names for references defined by SUB_BLOCK_REFS.  This list is used in some hier DP commands.
set child_blocks [ list ]
foreach block $SUB_BLOCK_REFS {lappend child_blocks [get_object_name [get_blocks -hier -filter block_name==$block]]}
set all_blocks "$child_blocks [get_object_name [current_block]]"
## Remove blocks only in top-level from block reference library list.
set top_block [current_block]
set remove_blocks [remove_from_collection [get_block -hier] $child_blocks]
foreach ref ${SUB_BLOCK_REFS} {
  if {[lsearch $SUB_BB_BLOCK_REFS $ref] < 0} {
    current_lib ${ref}${LIBRARY_SUFFIX}
    foreach_in_collection block $remove_blocks {
      set remove_lib [get_attribute $block lib]
      set_ref_libs -remove $remove_lib
    }
    current_block $top_block
  }
}
current_block $top_block

## Add child block reference to parent block
foreach inst ${SUB_BLOCK_INSTS} {
   # Add a reference to any child blocks
   set ref_lib_name ${WORK_DIR}/[get_attribute [get_cells $inst] ref_lib_name]
   set parent_ref_lib_name [get_attribute [get_cells $inst] parent_block.lib_name]
   # Check to see if ref lib already exists in the case of MIB
   if {[lsearch [get_attribute [get_libs $parent_ref_lib_name] ref_libs] "[file normalize ${ref_lib_name}]"] < 0} {
      puts "RM-info : Adding ${ref_lib_name} as a reference of ${parent_ref_lib_name}"
      set_ref_libs -library ${parent_ref_lib_name} -add [file normalize ${ref_lib_name}]
   }
}

########################################################################
## Loading the constraints into the committed blocks
########################################################################
if {$NETLIST2GDS_FLOW && $DP_HIGH_CAPACITY_MODE} {
  ## Constraint loading is delayed until needed in the N2G high capacity flow.
} else {
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
if {[file exists $DP_VA_MAP_FILE] } {
  foreach hier_inst_name $SUB_BLOCK_INSTS {
    puts "RM-info: Pushing down VA for $hier_inst_name ..."
    set hier_inst [get_cells $hier_inst_name]
    rm_push_down_voltage_areas -cell $hier_inst -map $DP_VA_MAP_FILE
  }
}

## Push-down user attr, if already defined.
set cur_compile_fusion_step [get_attribute -quiet [current_block] compile_fusion_step]
if {$cur_compile_fusion_step != ""} {
  foreach inst ${SUB_BLOCK_INSTS} {
    set_working_design -push $inst
    set_attribute [current_block] compile_fusion_step $cur_compile_fusion_step
    set_working_design -pop -level 0
  }
}
if {$HPC_CORE != ""} {
  rm_source -file ${HPC_UTILITIES_DIR}/dp.pushdown.tcl -optional -print "HPC_PUSHDOWN_OBJECTS_FILE"  
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
if {$HPC_CORE != ""} {rm_source -file ${HPC_PLUGINS_DIR}/commit_block_post_script.tcl optional -print "HPC_COMMIT_BLOCK_POST_SCRIPT"}

save_lib -all

redirect -tee -file ${REPORTS_DIR}/${REPORT_PREFIX}/run_end.rpt {run_end}

write_qor_data -report_list "performance host_machine report_app_options" -label $REPORT_PREFIX -output $WRITE_QOR_DATA_DIR

report_msg -summary
print_message_info -ids * -summary
echo [date] > commit_blocks

exit 

