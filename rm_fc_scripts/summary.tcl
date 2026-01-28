##########################################################################################
# Script: summary.tcl
# Version: V-2023.12-SP4
# Copyright (C) 2014-2024 Synopsys, Inc. All rights reserved.
##########################################################################################

source ./rm_utilities/procs_global.tcl 
source ./rm_utilities/procs_fc.tcl 
rm_source -file ./rm_setup/design_setup.tcl
rm_source -file ./rm_setup/fc_setup.tcl
rm_source -file ./rm_setup/header_fc.tcl
if {[file exists [which config_setup.tcl]]} {
	rm_source -file config_setup.tcl -after_file technology_override.tcl
} else {
	rm_source -file sidefile_setup.tcl -after_file technology_override.tcl
}

####################################
## Summary Report
####################################			 
if {$REPORT_QOR} {
	set REPORT_PREFIX summary
	rm_source -file print_results.tcl
        print_results -tns_sig_digits 2 -outfile ${REPORTS_DIR}/${REPORT_PREFIX}.rpt
	## Specify -tns_sig_digits N to display N digits for the TNS results in the report. Default is 0
}

print_message_info -ids * -summary
exit 
