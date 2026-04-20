namespace eval ::cliff::cmd {
    proc describe {argv} {
        if {[llength $argv] != 1} { error "usage: cliff describe <profile>" }
        set name [lindex $argv 0]
        set path [file join $::CLIFF_ROOT profiles $name.tcl]
        if {![file exists $path]} { error "no such profile: $name" }
        set prof [cliff::profile::load_file $path]
        cliff::validate::resolved $prof
        puts "# resolved profile: $name"
        dict for {k v} $prof {
            puts "$k: $v"
        }
    }
}
