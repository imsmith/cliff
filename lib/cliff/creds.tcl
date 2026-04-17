namespace eval ::cliff::creds {
    # Returns a dict: cred-name -> bytes produced by the helper (raw stdout).
    proc materialize {profile} {
        set out [dict create]
        if {![dict exists $profile creds]} { return $out }
        dict for {name entry} [dict get $profile creds] {
            if {![dict exists $entry helper]} {
                error "creds: entry '$name' missing helper="
            }
            set helper_name [dict get $entry helper]
            set helper_path [file join $::CLIFF_ROOT helpers $helper_name.tcl]
            if {![file exists $helper_path]} {
                error "creds: unknown helper: $helper_name"
            }
            set args [expr {[dict exists $entry args] ? [dict get $entry args] : ""}]
            set bytes [exec tclsh $helper_path $args]
            dict set out $name $bytes
        }
        return $out
    }
}
