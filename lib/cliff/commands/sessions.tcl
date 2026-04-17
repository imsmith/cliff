namespace eval ::cliff::cmd {
    proc sessions {argv} {
        set base [file join $::env(HOME) .local share cliff sessions]
        if {![file exists $base]} { return }
        foreach d [lsort [glob -nocomplain -directory $base -type d *]] {
            set id [file tail $d]
            set exit_code "?"
            if {[file exists [file join $d exit]]} {
                set fh [open [file join $d exit] r]; set exit_code [string trim [read $fh]]; close $fh
            }
            set when [clock format [file mtime $d] -format {%Y-%m-%d %H:%M}]
            puts [format "%s  %s  exit=%s" $id $when $exit_code]
        }
    }
}
