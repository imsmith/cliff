namespace eval ::cliff::docker {
    proc build_argv {args} {
        array set A {session_id "" profile "" project "" command ""}
        array set A $args
        set p $A(profile)

        set argv [list docker run --rm -i \
            --name cliff-$A(session_id) \
            --hostname cliff-$A(session_id) \
            --user devuser \
            --read-only \
            --cap-drop ALL \
            --security-opt no-new-privileges \
            --tmpfs /tmp:rw,size=256m,mode=1777 \
            --tmpfs /run/creds:rw,size=8m,mode=0700,uid=1000,gid=1000]

        # Network: none if no egress allow entries; session network otherwise
        set has_egress 0
        if {[dict exists $p egress allow] && [llength [dict get $p egress allow]] > 0} {
            set has_egress 1
        }
        if {$has_egress} {
            lappend argv --network cliff-$A(session_id)
        } else {
            lappend argv --network none
        }

        # Workspace
        set ws_mode ro
        if {[dict exists $p workspace mode]} { set ws_mode [dict get $p workspace mode] }
        if {$A(project) ne ""} {
            lappend argv --volume $A(project):/workspace:$ws_mode
        }

        # Home
        set home_size 512m
        if {[dict exists $p home size]} { set home_size [dict get $p home size] }
        lappend argv --tmpfs /home/devuser:rw,size=$home_size,mode=0700

        # Limits
        if {[dict exists $p limits cpus]}   { lappend argv --cpus [dict get $p limits cpus] }
        if {[dict exists $p limits memory]} { lappend argv --memory [dict get $p limits memory] }
        if {[dict exists $p limits pids]}   { lappend argv --pids-limit [dict get $p limits pids] }

        # Env
        if {[dict exists $p env]} {
            dict for {k v} [dict get $p env] {
                lappend argv --env $k=$v
            }
        }

        # Image and command
        lappend argv [dict get $p image]
        if {$A(command) ne ""} {
            foreach tok $A(command) { lappend argv $tok }
        }
        return $argv
    }
}
