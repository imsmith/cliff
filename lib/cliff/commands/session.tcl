namespace eval ::cliff::cmd {
    proc session {argv} {
        if {[llength $argv] != 1} { error "usage: cliff session <id>" }
        set id [lindex $argv 0]
        set d [file join $::env(HOME) .local share cliff sessions $id]
        if {![file isdirectory $d]} { error "no such session: $id" }
        foreach f {profile.tcl exit egress.log} {
            set p [file join $d $f]
            if {[file exists $p]} {
                puts "=== $f ==="
                set fh [open $p r]; puts [read $fh]; close $fh
            }
        }
    }
}
