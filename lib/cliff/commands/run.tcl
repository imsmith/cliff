source [file join $::CLIFF_ROOT lib cliff session.tcl]
source [file join $::CLIFF_ROOT lib cliff creds.tcl]
source [file join $::CLIFF_ROOT lib cliff egress.tcl]

namespace eval ::cliff::cmd {
    proc run {argv} {
        if {[llength $argv] < 1} { error "usage: cliff run <profile> \[--project=<path>\]" }
        set profile [lindex $argv 0]
        set project ""
        foreach a [lrange $argv 1 end] {
            if {[regexp {^--project=(.+)$} $a -> v]} { set project $v }
        }
        exit [cliff::session::run $profile project $project interactive 1]
    }
}
