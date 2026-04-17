source [file join $::CLIFF_ROOT lib cliff session.tcl]
source [file join $::CLIFF_ROOT lib cliff creds.tcl]
source [file join $::CLIFF_ROOT lib cliff egress.tcl]

namespace eval ::cliff::cmd {
    proc exec {argv} {
        if {[llength $argv] < 3} { error "usage: cliff exec <profile> --project=<path> -- <cmd...>" }
        set profile [lindex $argv 0]
        set project ""
        set command ""
        set i 1
        while {$i < [llength $argv]} {
            set a [lindex $argv $i]
            if {[regexp {^--project=(.+)$} $a -> v]} { set project $v; incr i } \
            elseif {$a eq "--"} { set command [lrange $argv [expr {$i+1}] end]; break } \
            else { incr i }
        }
        exit [cliff::session::run $profile project $project command $command interactive 0]
    }
}
