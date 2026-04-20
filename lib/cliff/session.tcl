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

    proc run {profile_name args} {
        array set A {project "" command "" interactive 1}
        array set A $args

        set profile_path [file join $::CLIFF_ROOT profiles $profile_name.tcl]
        if {![file exists $profile_path]} { error "no such profile: $profile_name" }
        set profile [cliff::profile::load_file $profile_path]
        cliff::validate::resolved $profile

        set id [new_id $profile_name]
        set sdir [session_dir $id]

        # Record resolved profile
        set fh [open [file join $sdir profile.tcl] w]
        puts $fh "# resolved profile for session $id"
        dict for {k v} $profile { puts $fh "$k: $v" }
        close $fh

        # Materialize creds (currently no-op if profile has none)
        set creds [cliff::creds::materialize $profile]

        # Start egress sidecar if needed
        set need_egress [cliff::egress::needs_sidecar $profile]
        if {$need_egress} {
            exec docker network create cliff-$id >&@ stderr
            set allowlist [cliff::egress::render_allowlist [dict get $profile egress allow]]
            set egress_cid [exec docker run -d \
                --name cliff-egress-$id \
                --network cliff-$id \
                --read-only \
                --tmpfs /tmp --tmpfs /var \
                --cap-drop ALL --cap-add NET_BIND_SERVICE --cap-add DAC_OVERRIDE \
                --security-opt no-new-privileges \
                -e CLIFF_ALLOWLIST=$allowlist \
                -v $sdir:/opt/cliff/log:rw \
                cliff-egress:0.3.0]
            # Wait for mitmproxy to be ready on port 3128 (max 10s)
            set ready 0
            for {set t 0} {$t < 20} {incr t} {
                if {![catch {exec docker exec cliff-egress-$id sh -c {nc -z 127.0.0.1 3128}} ]} {
                    set ready 1; break
                }
                after 500
            }
            if {!$ready} { error "egress sidecar did not become ready in 10s" }
        }

        # Build app-container argv
        set command $A(command)
        if {$command eq ""} { set command {/bin/sh -l} }
        set argv [cliff::docker::build_argv \
            session_id $id \
            profile $profile \
            project $A(project) \
            command $command]

        # Inject egress env + DNS: insert before the image name so docker sees
        # these as options, not as arguments to the container command.
        if {$need_egress} {
            # Resolve egress container IP (--dns requires an IP, not a name).
            set egress_ip [string trim [exec docker inspect \
                -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" \
                cliff-egress-$id]]
            set img [dict get $profile image]
            set img_idx [lsearch -exact $argv $img]
            set egress_opts [list \
                --dns $egress_ip \
                --env http_proxy=http://cliff-egress-$id:3128 \
                --env https_proxy=http://cliff-egress-$id:3128 \
                --env HTTP_PROXY=http://cliff-egress-$id:3128 \
                --env HTTPS_PROXY=http://cliff-egress-$id:3128]
            set argv [linsert $argv $img_idx {*}$egress_opts]
        }

        # For interactive sessions, swap -i with -it
        if {$A(interactive)} {
            set idx [lsearch $argv "-i"]
            if {$idx >= 0} { set argv [lreplace $argv $idx $idx -it] }
        }

        # Two-stage: docker create → docker cp creds → docker start -ai

        # Replace "docker run" with "docker create"; drop --rm (not valid with create).
        set create_argv [lreplace $argv 0 1 docker create]
        set idx [lsearch $create_argv "--rm"]
        if {$idx >= 0} { set create_argv [lreplace $create_argv $idx $idx] }

        set container_id [string trim [exec {*}$create_argv]]

        # Write creds into /run/creds inside the container.
        dict for {name bytes} $creds {
            set tmp_path [file join /tmp cliff-creds-[pid]-[clock microseconds]-$name]
            set fh [open $tmp_path w 0600]
            puts -nonewline $fh $bytes
            close $fh
            exec docker cp $tmp_path $container_id:/run/creds/$name
            file delete $tmp_path
        }

        set exit_code 0
        set start_flags [expr {$A(interactive) ? "-ai" : "-a"}]
        if {[catch {
            exec docker start $start_flags $container_id >@stdout 2>@stderr <@stdin
        } err]} {
            set exit_code 1
            puts stderr "cliff: session $id failed: $err"
        }
        catch { exec docker rm -f $container_id }

        # Teardown: give mitmdump a moment to flush remaining log lines
        # before docker stop sends SIGTERM.
        if {$need_egress} {
            after 1000
            catch { exec docker stop cliff-egress-$id }
            catch { exec docker rm -f cliff-egress-$id }
            catch { exec docker network rm cliff-$id }
        }

        # Record exit
        set fh [open [file join $sdir exit] w]
        puts $fh $exit_code
        close $fh

        return $exit_code
    }
}
