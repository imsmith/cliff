namespace eval ::cliff::profile {
    variable _state

    proc parse_string {src} {
        variable _state
        set _state [dict create]
        set slave [interp create -safe]
        $slave alias image ::cliff::profile::_set image
        $slave eval $src
        interp delete $slave
        return $_state
    }

    proc _set {key value} {
        variable _state
        dict set _state $key $value
    }
}
