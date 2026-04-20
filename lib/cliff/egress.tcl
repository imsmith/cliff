namespace eval ::cliff::egress {
    proc render_allowlist {entries} {
        return [join $entries "\n"]
    }
    proc needs_sidecar {profile} {
        return [expr {[dict exists $profile egress allow] \
                      && [llength [dict get $profile egress allow]] > 0}]
    }
}
