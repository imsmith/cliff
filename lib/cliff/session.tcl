# Try tcllib's sha256 package; if unavailable, fall back to sha256sum(1).
if {[catch {package require sha256}]} {
    # Fallback: none of the sha256 procs available; we'll use exec.
}

namespace eval ::cliff::session {
    proc new_id {profile} {
        set seed "[clock microseconds]-$profile-[pid]-[expr {rand()}]"
        if {![catch {package present sha256}]} {
            set id [string range [::sha2::sha256 -hex $seed] 0 11]
        } else {
            # Use sha256sum command
            set id [string range [exec sh -c "printf '%s' '$seed' | sha256sum | awk '{print \$1}'"] 0 11]
        }
        return $id
    }

    proc session_dir {id} {
        set base [file join $::env(HOME) .local share cliff sessions]
        file mkdir $base
        set d [file join $base $id]
        file mkdir $d
        return $d
    }
}
