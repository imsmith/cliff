namespace eval ::cliff::validate {
    proc resolved {profile} {
        if {![dict exists $profile image]} {
            error "profile: image field is required"
        }
        if {[dict exists $profile workspace mode]} {
            set m [dict get $profile workspace mode]
            if {$m ni {ro rw}} {
                error "profile: workspace mode must be 'ro' or 'rw', got: $m"
            }
        }
        if {[dict exists $profile egress allow]} {
            foreach entry [dict get $profile egress allow] {
                if {![regexp {^[A-Za-z0-9.*_-]+:\d+$} $entry]} {
                    error "profile: egress allow entry must be host:port, got: $entry"
                }
            }
        }
        return "ok"
    }
}
