namespace eval ::cliff::cmd {
    proc list {argv} {
        set pdir [file join $::CLIFF_ROOT profiles]
        foreach f [lsort [glob -nocomplain -directory $pdir *.tcl]] {
            set name [file rootname [file tail $f]]
            set prof [cliff::profile::load_file $f]
            set desc ""
            if {[dict exists $prof describe]} { set desc [dict get $prof describe] }
            set img ""
            if {[dict exists $prof image]} { set img [dict get $prof image] }
            puts [format "%-20s %-50s %s" $name $desc $img]
        }
    }
}
