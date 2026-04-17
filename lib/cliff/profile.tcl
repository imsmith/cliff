namespace eval ::cliff::profile {
    variable _state

    proc parse_string {src} {
        variable _state
        set _state [dict create egress [dict create allow [list] deny [list]]]
        set slave [interp create -safe]
        foreach cmd {describe image} { $slave alias $cmd ::cliff::profile::_set $cmd }
        foreach cmd {workspace home} { $slave alias $cmd ::cliff::profile::_set_kv $cmd }
        $slave alias egress ::cliff::profile::_block_egress
        $slave alias limits ::cliff::profile::_block_limits
        $slave alias env    ::cliff::profile::_block_env
        $slave alias creds  ::cliff::profile::_block_creds
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

    # egress block: lines of `allow <pattern>` or `deny <pattern>`
    proc _block_egress {body} {
        variable _state
        set allow [list]
        set deny [list]
        foreach line [split $body "\n;"] {
            set line [string trim $line]
            if {$line eq "" || [string index $line 0] eq "#"} continue
            set parts [regexp -inline -all {\S+} $line]
            set verb [lindex $parts 0]
            set pat  [lindex $parts 1]
            if {$verb eq "allow"} {
                lappend allow $pat
            } elseif {$verb eq "deny"} {
                lappend deny $pat
            } else {
                error "profile: egress block: expected allow/deny, got: $verb"
            }
        }
        dict set _state egress allow $allow
        dict set _state egress deny $deny
    }

    # _block_limits / _block_env: named wrappers so aliases resolve correctly
    proc _block_limits {body} { _block_kv limits $body }
    proc _block_env    {body} { _block_kv env    $body }

    # limits/env blocks: simple key value pairs, one per line
    proc _block_kv {key body} {
        variable _state
        set m [dict create]
        foreach line [split $body "\n;"] {
            set line [string trim $line]
            if {$line eq "" || [string index $line 0] eq "#"} continue
            set parts [regexp -inline -all {\S+} $line]
            if {[llength $parts] < 2} {
                error "profile: $key block: expected 'key value', got: $line"
            }
            dict set m [lindex $parts 0] [join [lrange $parts 1 end]]
        }
        dict set _state $key $m
    }

    # creds block: each entry is `<name> helper=X args={...}` or `key=plain`
    # Tokenizes with regex so brace-quoted values (with spaces) are kept intact.
    proc _block_creds {body} {
        variable _state
        set m [dict create]
        # pattern: key={braced value} | any non-whitespace token
        set tok_pat {[^\s=]+=\{[^\}]*\}|[^\s]+}
        foreach line [split $body "\n"] {
            set line [string trim $line]
            if {$line eq "" || [string index $line 0] eq "#"} continue
            set parts [regexp -inline -all -- $tok_pat $line]
            if {[llength $parts] < 1} continue
            set name [lindex $parts 0]
            set entry [dict create]
            foreach p [lrange $parts 1 end] {
                if {![regexp {^([^=]+)=(.*)$} $p -> k v]} {
                    error "profile: creds: expected key=value, got: $p"
                }
                set v [string trim $v "{}"]
                dict set entry $k $v
            }
            dict set m $name $entry
        }
        dict set _state creds $m
    }
}
