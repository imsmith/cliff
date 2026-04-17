namespace eval ::cliff::profile {
    variable _state

    proc parse_string {src} {
        variable _state
        set _state [dict create]
        set slave [interp create -safe]
        foreach cmd {describe image} {
            $slave alias $cmd ::cliff::profile::_set $cmd
        }
        foreach cmd {workspace home} {
            $slave alias $cmd ::cliff::profile::_set_kv $cmd
        }
        $slave eval $src
        interp delete $slave
        return $_state
    }

    proc _set {key value} {
        variable _state
        dict set _state $key $value
    }

    proc _set_kv {key args} {
        variable _state
        set m [dict create]
        foreach pair $args {
            if {![regexp {^([^=]+)=(.*)$} $pair -> k v]} {
                error "profile: expected key=value, got: $pair"
            }
            dict set m $k $v
        }
        dict set _state $key $m
    }
}
