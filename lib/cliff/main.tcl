namespace eval ::cliff::main {
    proc dispatch {argv} {
        if {[llength $argv] < 1} { usage; exit 2 }
        set cmd [lindex $argv 0]
        set rest [lrange $argv 1 end]
        set cmdfile [file join $::CLIFF_ROOT lib cliff commands $cmd.tcl]
        if {![file exists $cmdfile]} {
            puts stderr "cliff: unknown subcommand: $cmd"
            usage
            exit 2
        }
        source [file join $::CLIFF_ROOT lib cliff profile.tcl]
        source [file join $::CLIFF_ROOT lib cliff validate.tcl]
        source [file join $::CLIFF_ROOT lib cliff docker.tcl]
        source $cmdfile
        ::cliff::cmd::$cmd $rest
    }
    proc usage {} {
        puts stderr "usage: cliff <run|exec|list|describe|sessions|session> \[args...\]"
    }
}
