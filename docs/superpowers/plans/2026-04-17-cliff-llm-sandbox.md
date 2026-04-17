# Cliff LLM Sandbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Cliff v0.3.0 LLM sandbox — a `cliff` tcl CLI that launches hardened, profile-driven, ephemeral container sessions with credential scoping and egress allowlisting, safe for LLMs to drive without human babysitting.

**Architecture:** A single tcl entry point (`bin/cliff`) parses a profile (tcl file, single-parent inheritance, wholesale block replacement), runs credential helpers on the host, renders an mitmproxy allowlist, creates a per-session docker network with an egress sidecar, starts the app container with hardened defaults (read-only rootfs, dropped caps, tmpfs home, non-root devuser), and cleans everything up on exit. All state is ephemeral except the host workspace mount and a session log directory.

**Tech Stack:** Tcl 8.6 (wrapper + profile parser via safe slave interp, tcltest for unit tests), Docker (rootful, host engine), mitmproxy (egress proxy, cliff-signed CA baked into images), Alpine Linux base images (existing), bash (integration tests).

---

## File Structure

**New files:**

```
bin/
  cliff                        # Tcl entry point; sources lib/, dispatches subcommands
lib/cliff/
  main.tcl                     # Subcommand dispatcher; shared init
  profile.tcl                  # Profile loader: safe slave interp, inheritance resolution
  validate.tcl                 # Profile validation (required fields, type checks)
  docker.tcl                   # Resolved-profile → docker run argv (pure)
  creds.tcl                    # Cred-helper invocation on host; tmpfs population
  egress.tcl                   # Allowlist → mitmproxy config, DNS stub config
  session.tcl                  # Session lifecycle: network, containers, teardown
  commands/
    run.tcl                    # `cliff run`
    exec.tcl                   # `cliff exec`
    list.tcl                   # `cliff list`
    describe.tcl               # `cliff describe`
    sessions.tcl               # `cliff sessions`, `cliff session <id>`
profiles/
  base.tcl
  dev-offline.tcl
  dev-aws-read.tcl
  dev-aws-write.tcl
  obsv-local.tcl
  yolo-dev.tcl
helpers/
  aws-sts.tcl                  # AWS STS assume-role helper
images/
  egress/
    Dockerfile                 # Alpine + mitmproxy + dnsmasq + config templates
    entrypoint.sh              # Render configs at start, launch services
    mitmproxy-addon.py         # Path/host allowlist enforcement
  ca/
    cliff-egress.crt           # Generated CA cert (checked in, derived from key)
    cliff-egress.key           # Generated CA key (NOT checked in; gitignored)
    generate.sh                # Produces the pair
test/
  unit/
    all.tcl                    # tcltest runner
    profile_parse_test.tcl     # Profile parser unit tests
    profile_inherit_test.tcl   # Inheritance resolution tests
    validate_test.tcl          # Validation tests
    docker_argv_test.tcl       # Docker command translation tests
    egress_render_test.tcl     # Allowlist rendering tests
  integration/
    harness.sh                 # Shared setup/teardown helpers
    enforcement_fs.sh          # Workspace ro, home tmpfs, persistence
    enforcement_net.sh         # Egress deny, allowlist, DNS
    enforcement_creds.sh       # No host cred mounts, tmpfs cleanup
    enforcement_limits.sh      # Pids, memory, read-only rootfs
    lifecycle.sh               # list, describe, sessions, session <id>
```

**Modified files:**

```
build/Dockerfile.base          # Add cliff-egress CA, /etc/skel dotfiles, ensure devuser
build/Dockerfile.dev           # (unchanged; inherits CA via FROM base)
build/Dockerfile.obsv          # (unchanged)
build/Dockerfile.full          # (unchanged)
Makefile                       # Add: test-unit, test-integration, build-egress, gen-ca
README.md                      # Document cliff CLI + profile model
CLAUDE.md                      # Update status to v0.3.0 in-progress
.gitignore                     # Add images/ca/cliff-egress.key, ~/.local/share/cliff
docker-compose.yml             # (removed — cliff replaces compose-driven workflow; keep
                               #  legacy copy as docker-compose.legacy.yml for reference)
```

---

## Phase 1: Repository scaffolding

### Task 1: Create directory skeleton

**Files:**
- Create: `bin/`, `lib/cliff/`, `lib/cliff/commands/`, `profiles/`, `helpers/`, `images/egress/`, `images/ca/`, `test/unit/`, `test/integration/`

- [ ] **Step 1: Create directories and placeholders**

```bash
mkdir -p bin lib/cliff/commands profiles helpers images/egress images/ca test/unit test/integration
touch bin/.gitkeep lib/cliff/.gitkeep lib/cliff/commands/.gitkeep \
      profiles/.gitkeep helpers/.gitkeep images/egress/.gitkeep images/ca/.gitkeep \
      test/unit/.gitkeep test/integration/.gitkeep
```

- [ ] **Step 2: Update `.gitignore`**

Append to `.gitignore` (create if missing):

```
# Cliff sandbox
images/ca/cliff-egress.key
.cliff-sessions-test/
```

- [ ] **Step 3: Commit scaffolding**

```bash
git add .gitignore bin/ lib/ profiles/ helpers/ images/ test/
git commit -m "scaffold v0.3.0 sandbox directory layout"
```

---

## Phase 2: Profile parser (pure tcl, TDD)

The parser uses a Tcl *safe slave interpreter* with an explicit command whitelist. A profile tcl file is `source`d into the slave; declared commands record values into a dict; `inherit` recursively resolves a parent profile first, then the child overrides.

### Task 2: Stub the profile loader API

**Files:**
- Create: `lib/cliff/profile.tcl`
- Test: `test/unit/profile_parse_test.tcl`, `test/unit/all.tcl`

- [ ] **Step 1: Write the tcltest runner**

`test/unit/all.tcl`:

```tcl
#!/usr/bin/env tclsh
package require tcltest
namespace import ::tcltest::*
configure -testdir [file dirname [info script]] -verbose {pass fail error}
runAllTests
exit [expr {$::tcltest::numTests(Failed) > 0}]
```

- [ ] **Step 2: Write the first failing test**

`test/unit/profile_parse_test.tcl`:

```tcl
package require tcltest
namespace import ::tcltest::*

source [file join [file dirname [info script]] .. .. lib cliff profile.tcl]

test profile-parse-minimal {parses an image-only profile} -body {
    set result [cliff::profile::parse_string "image cliff-base:0.2.0"]
    dict get $result image
} -result "cliff-base:0.2.0"

cleanupTests
```

- [ ] **Step 3: Run test — expect failure**

Run: `tclsh test/unit/all.tcl`
Expected: FAIL — `cliff::profile::parse_string` does not exist.

- [ ] **Step 4: Minimal implementation**

`lib/cliff/profile.tcl`:

```tcl
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
```

- [ ] **Step 5: Run test — expect pass**

Run: `tclsh test/unit/all.tcl`
Expected: PASS (1/1).

- [ ] **Step 6: Commit**

```bash
git add lib/cliff/profile.tcl test/unit/all.tcl test/unit/profile_parse_test.tcl
git commit -m "profile: parse minimal image declaration"
```

### Task 3: Scalar directives — describe, image, workspace, home

**Files:**
- Modify: `lib/cliff/profile.tcl`
- Modify: `test/unit/profile_parse_test.tcl`

- [ ] **Step 1: Write failing tests**

Append to `test/unit/profile_parse_test.tcl` (before `cleanupTests`):

```tcl
test profile-parse-describe {parses describe string} -body {
    set r [cliff::profile::parse_string {
        describe "Test profile"
        image cliff-base:0.2.0
    }]
    dict get $r describe
} -result "Test profile"

test profile-parse-workspace {parses workspace kv line} -body {
    set r [cliff::profile::parse_string {
        image cliff-base:0.2.0
        workspace mode=ro
    }]
    dict get $r workspace mode
} -result "ro"

test profile-parse-home {parses home kv line with multiple pairs} -body {
    set r [cliff::profile::parse_string {
        image cliff-base:0.2.0
        home mode=tmpfs size=512m
    }]
    list [dict get $r home mode] [dict get $r home size]
} -result {tmpfs 512m}
```

- [ ] **Step 2: Run — expect 3 failures**

Run: `tclsh test/unit/all.tcl`
Expected: FAIL (3/4) — unknown aliases for `describe`, `workspace`, `home`.

- [ ] **Step 3: Implement**

Replace the body of `namespace eval ::cliff::profile` in `lib/cliff/profile.tcl`:

```tcl
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
```

- [ ] **Step 4: Run — expect all pass**

Run: `tclsh test/unit/all.tcl`
Expected: PASS (4/4).

- [ ] **Step 5: Commit**

```bash
git add lib/cliff/profile.tcl test/unit/profile_parse_test.tcl
git commit -m "profile: support describe, image, workspace, home directives"
```

### Task 4: Block directives — creds, egress, limits, env

**Files:**
- Modify: `lib/cliff/profile.tcl`
- Modify: `test/unit/profile_parse_test.tcl`

- [ ] **Step 1: Write failing tests**

Append to `test/unit/profile_parse_test.tcl`:

```tcl
test profile-parse-egress {parses egress block with multiple allow lines} -body {
    set r [cliff::profile::parse_string {
        image cliff-base:0.2.0
        egress {
            allow *.amazonaws.com:443
            allow registry-1.docker.io:443
        }
    }]
    dict get $r egress allow
} -result {*.amazonaws.com:443 registry-1.docker.io:443}

test profile-parse-limits {parses limits block kv pairs} -body {
    set r [cliff::profile::parse_string {
        image cliff-base:0.2.0
        limits { cpus 2; memory 4g; pids 512 }
    }]
    list [dict get $r limits cpus] [dict get $r limits memory] [dict get $r limits pids]
} -result {2 4g 512}

test profile-parse-env {parses env block} -body {
    set r [cliff::profile::parse_string {
        image cliff-base:0.2.0
        env { AWS_REGION us-east-1 }
    }]
    dict get $r env AWS_REGION
} -result "us-east-1"

test profile-parse-creds {parses creds block with helper args} -body {
    set r [cliff::profile::parse_string {
        image cliff-base:0.2.0
        creds {
            aws helper=aws-sts args={role=arn:aws:iam::1:role/r ttl=1h}
        }
    }]
    list [dict get $r creds aws helper] [dict get $r creds aws args]
} -result {aws-sts {role=arn:aws:iam::1:role/r ttl=1h}}
```

- [ ] **Step 2: Run — expect failures**

Run: `tclsh test/unit/all.tcl`
Expected: FAIL — block directives unknown.

- [ ] **Step 3: Implement block parsing**

Add to `lib/cliff/profile.tcl` inside the namespace:

```tcl
    # egress block: lines of `allow <pattern>` or `deny <pattern>`
    proc _block_egress {body} {
        variable _state
        set allow [list]
        set deny [list]
        set slave [interp create -safe]
        $slave alias allow [list apply {{listvar pat} {
            upvar 2 $listvar l
            lappend l $pat
        }} allow]
        $slave alias deny [list apply {{listvar pat} {
            upvar 2 $listvar l
            lappend l $pat
        }} deny]
        $slave eval $body
        interp delete $slave
        dict set _state egress allow $allow
        dict set _state egress deny $deny
    }

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

    # creds block: each entry is `<name> helper=X args=Y`
    proc _block_creds {body} {
        variable _state
        set m [dict create]
        foreach line [split $body "\n;"] {
            set line [string trim $line]
            if {$line eq "" || [string index $line 0] eq "#"} continue
            set parts [regexp -inline -all {\S+} $line]
            set name [lindex $parts 0]
            set entry [dict create]
            foreach p [lrange $parts 1 end] {
                if {![regexp {^([^=]+)=(.*)$} $p -> k v]} {
                    error "profile: creds: expected key=value, got: $p"
                }
                # Strip surrounding braces if present
                set v [string trim $v "{}"]
                dict set entry $k $v
            }
            dict set m $name $entry
        }
        dict set _state creds $name $entry
    }
```

Replace `parse_string` to wire up the new aliases:

```tcl
    proc parse_string {src} {
        variable _state
        set _state [dict create egress [dict create allow [list] deny [list]]]
        set slave [interp create -safe]
        foreach cmd {describe image} { $slave alias $cmd ::cliff::profile::_set $cmd }
        foreach cmd {workspace home} { $slave alias $cmd ::cliff::profile::_set_kv $cmd }
        $slave alias egress ::cliff::profile::_block_egress
        $slave alias limits [list ::cliff::profile::_block_kv limits]
        $slave alias env    [list ::cliff::profile::_block_kv env]
        $slave alias creds  ::cliff::profile::_block_creds
        $slave eval $src
        interp delete $slave
        return $_state
    }
```

- [ ] **Step 4: Fix `_block_creds` — the current implementation only stores the last entry. Rewrite to accumulate properly:**

```tcl
    proc _block_creds {body} {
        variable _state
        set m [dict create]
        foreach line [split $body "\n;"] {
            set line [string trim $line]
            if {$line eq "" || [string index $line 0] eq "#"} continue
            set parts [regexp -inline -all {\S+} $line]
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
```

- [ ] **Step 5: Run tests — expect all pass**

Run: `tclsh test/unit/all.tcl`
Expected: PASS (8/8).

- [ ] **Step 6: Commit**

```bash
git add lib/cliff/profile.tcl test/unit/profile_parse_test.tcl
git commit -m "profile: parse egress, limits, env, creds blocks"
```

### Task 5: Inheritance resolution

**Files:**
- Create: `test/unit/profile_inherit_test.tcl`
- Modify: `lib/cliff/profile.tcl`

- [ ] **Step 1: Write failing tests**

`test/unit/profile_inherit_test.tcl`:

```tcl
package require tcltest
namespace import ::tcltest::*

source [file join [file dirname [info script]] .. .. lib cliff profile.tcl]

set FIXDIR [file join [file dirname [info script]] fixtures]

test inherit-resolves-parent {child inherits parent image when not overridden} -setup {
    file mkdir $FIXDIR
    set fh [open $FIXDIR/parent.tcl w]; puts $fh {image cliff-base:0.2.0}; close $fh
    set fh [open $FIXDIR/child.tcl w]; puts $fh {inherit parent}; close $fh
} -body {
    set r [cliff::profile::load_file $FIXDIR/child.tcl]
    dict get $r image
} -cleanup {
    file delete -force $FIXDIR
} -result "cliff-base:0.2.0"

test inherit-child-overrides {child overrides parent wholesale per block} -setup {
    file mkdir $FIXDIR
    set fh [open $FIXDIR/parent.tcl w]; puts $fh {
        image cliff-base:0.2.0
        egress { allow foo.com:443 }
    }; close $fh
    set fh [open $FIXDIR/child.tcl w]; puts $fh {
        inherit parent
        egress { allow bar.com:443 }
    }; close $fh
} -body {
    set r [cliff::profile::load_file $FIXDIR/child.tcl]
    dict get $r egress allow
} -cleanup {
    file delete -force $FIXDIR
} -result {bar.com:443}

test inherit-cycle-detected {cycles fail loud} -setup {
    file mkdir $FIXDIR
    set fh [open $FIXDIR/a.tcl w]; puts $fh {inherit b}; close $fh
    set fh [open $FIXDIR/b.tcl w]; puts $fh {inherit a}; close $fh
} -body {
    catch {cliff::profile::load_file $FIXDIR/a.tcl} err
    set err
} -cleanup {
    file delete -force $FIXDIR
} -match glob -result "*cycle*"

cleanupTests
```

- [ ] **Step 2: Run — expect failures**

Run: `tclsh test/unit/all.tcl`
Expected: FAIL — `load_file` does not exist.

- [ ] **Step 3: Implement `load_file` with inheritance**

Add to `lib/cliff/profile.tcl`:

```tcl
    variable _load_stack [list]

    proc load_file {path} {
        variable _load_stack
        set abs [file normalize $path]
        if {$abs in $_load_stack} {
            error "profile: inheritance cycle: $_load_stack -> $abs"
        }
        lappend _load_stack $abs
        set fh [open $path r]
        set src [read $fh]
        close $fh

        # Two-pass: first extract `inherit <name>` lines, load parent, then apply child.
        set parent ""
        set remaining [list]
        foreach line [split $src "\n"] {
            set trimmed [string trim $line]
            if {[regexp {^inherit\s+(\S+)\s*$} $trimmed -> name]} {
                if {$parent ne ""} { error "profile: multiple inherit directives" }
                set parent $name
            } else {
                lappend remaining $line
            }
        }

        if {$parent ne ""} {
            set parent_path [file join [file dirname $abs] "$parent.tcl"]
            set result [load_file $parent_path]
        } else {
            set result [dict create egress [dict create allow [list] deny [list]]]
        }

        # Parse child src on top of parent state
        set child [parse_string [join $remaining "\n"]]
        foreach k [dict keys $child] {
            dict set result $k [dict get $child $k]
        }

        set _load_stack [lrange $_load_stack 0 end-1]
        return $result
    }
```

- [ ] **Step 4: Run tests — expect pass**

Run: `tclsh test/unit/all.tcl`
Expected: PASS (11/11).

- [ ] **Step 5: Commit**

```bash
git add lib/cliff/profile.tcl test/unit/profile_inherit_test.tcl
git commit -m "profile: single-parent inheritance with cycle detection"
```

---

## Phase 3: Validation

### Task 6: Required-field validation

**Files:**
- Create: `lib/cliff/validate.tcl`
- Create: `test/unit/validate_test.tcl`

- [ ] **Step 1: Write failing tests**

`test/unit/validate_test.tcl`:

```tcl
package require tcltest
namespace import ::tcltest::*

source [file join [file dirname [info script]] .. .. lib cliff profile.tcl]
source [file join [file dirname [info script]] .. .. lib cliff validate.tcl]

test validate-requires-image {image is required} -body {
    catch {cliff::validate::resolved [dict create]} err
    set err
} -match glob -result "*image*required*"

test validate-accepts-minimal {minimal valid profile passes} -body {
    cliff::validate::resolved [dict create image cliff-base:0.2.0]
} -result "ok"

test validate-workspace-mode {workspace mode must be ro or rw} -body {
    catch {cliff::validate::resolved [dict create \
        image cliff-base:0.2.0 \
        workspace [dict create mode badvalue]]} err
    set err
} -match glob -result "*workspace*mode*"

test validate-egress-format {egress allow entries must be host:port} -body {
    catch {cliff::validate::resolved [dict create \
        image cliff-base:0.2.0 \
        egress [dict create allow {not-a-hostport}]]} err
    set err
} -match glob -result "*egress*host:port*"

cleanupTests
```

- [ ] **Step 2: Run — expect failures**

Run: `tclsh test/unit/all.tcl`
Expected: FAIL — `cliff::validate::resolved` does not exist.

- [ ] **Step 3: Implement**

`lib/cliff/validate.tcl`:

```tcl
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
```

- [ ] **Step 4: Run — expect pass**

Run: `tclsh test/unit/all.tcl`
Expected: PASS (15/15).

- [ ] **Step 5: Commit**

```bash
git add lib/cliff/validate.tcl test/unit/validate_test.tcl
git commit -m "validate: required fields and format checks for resolved profile"
```

---

## Phase 4: Docker argv translation (pure)

### Task 7: Build docker-run argv from a resolved profile

**Files:**
- Create: `lib/cliff/docker.tcl`
- Create: `test/unit/docker_argv_test.tcl`

- [ ] **Step 1: Write failing tests**

`test/unit/docker_argv_test.tcl`:

```tcl
package require tcltest
namespace import ::tcltest::*

source [file join [file dirname [info script]] .. .. lib cliff docker.tcl]

proc contains {haystack needles} {
    foreach n $needles {
        if {[lsearch -exact $haystack $n] < 0} { return 0 }
    }
    return 1
}

test docker-argv-minimal {emits read-only rootfs and non-root user} -body {
    set argv [cliff::docker::build_argv \
        session_id abc123 \
        profile [dict create image cliff-base:0.2.0] \
        project /tmp/proj \
        command {/bin/sh -l}]
    contains $argv {--read-only --user devuser --security-opt no-new-privileges cliff-base:0.2.0}
} -result 1

test docker-argv-drops-caps {drops all caps by default} -body {
    set argv [cliff::docker::build_argv \
        session_id abc123 \
        profile [dict create image cliff-base:0.2.0] \
        project /tmp/proj \
        command {/bin/sh -l}]
    contains $argv {--cap-drop ALL}
} -result 1

test docker-argv-workspace-ro {bind-mounts workspace read-only} -body {
    set argv [cliff::docker::build_argv \
        session_id abc123 \
        profile [dict create \
            image cliff-base:0.2.0 \
            workspace [dict create mode ro]] \
        project /tmp/proj \
        command {/bin/sh -l}]
    contains $argv {--volume /tmp/proj:/workspace:ro}
} -result 1

test docker-argv-home-tmpfs {tmpfs home with size} -body {
    set argv [cliff::docker::build_argv \
        session_id abc123 \
        profile [dict create \
            image cliff-base:0.2.0 \
            home [dict create mode tmpfs size 512m]] \
        project /tmp/proj \
        command {/bin/sh -l}]
    contains $argv {--tmpfs /home/devuser:rw,size=512m,mode=0700}
} -result 1

test docker-argv-limits {applies cpu/memory/pids limits} -body {
    set argv [cliff::docker::build_argv \
        session_id abc123 \
        profile [dict create \
            image cliff-base:0.2.0 \
            limits [dict create cpus 2 memory 4g pids 512]] \
        project /tmp/proj \
        command {/bin/sh -l}]
    contains $argv {--cpus 2 --memory 4g --pids-limit 512}
} -result 1

test docker-argv-env {applies env vars} -body {
    set argv [cliff::docker::build_argv \
        session_id abc123 \
        profile [dict create \
            image cliff-base:0.2.0 \
            env [dict create AWS_REGION us-east-1]] \
        project /tmp/proj \
        command {/bin/sh -l}]
    contains $argv {--env AWS_REGION=us-east-1}
} -result 1

test docker-argv-network-none-for-no-egress {no egress allow => --network none} -body {
    set argv [cliff::docker::build_argv \
        session_id abc123 \
        profile [dict create image cliff-base:0.2.0] \
        project /tmp/proj \
        command {/bin/sh -l}]
    contains $argv {--network none}
} -result 1

test docker-argv-network-session-for-egress {egress allow => session-scoped network} -body {
    set argv [cliff::docker::build_argv \
        session_id abc123 \
        profile [dict create \
            image cliff-base:0.2.0 \
            egress [dict create allow {foo.com:443} deny {}]] \
        project /tmp/proj \
        command {/bin/sh -l}]
    contains $argv {--network cliff-abc123}
} -result 1

cleanupTests
```

- [ ] **Step 2: Run — expect failures**

Run: `tclsh test/unit/all.tcl`
Expected: FAIL — `cliff::docker::build_argv` not defined.

- [ ] **Step 3: Implement**

`lib/cliff/docker.tcl`:

```tcl
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
```

- [ ] **Step 4: Run tests — expect pass**

Run: `tclsh test/unit/all.tcl`
Expected: PASS (23/23).

- [ ] **Step 5: Commit**

```bash
git add lib/cliff/docker.tcl test/unit/docker_argv_test.tcl
git commit -m "docker: build hardened docker run argv from resolved profile"
```

---

## Phase 5: CLI skeleton + `list` + `describe`

### Task 8: Main dispatcher

**Files:**
- Create: `bin/cliff`
- Create: `lib/cliff/main.tcl`
- Create: `lib/cliff/commands/list.tcl`
- Create: `lib/cliff/commands/describe.tcl`

- [ ] **Step 1: Write the entry point**

`bin/cliff`:

```tcl
#!/usr/bin/env tclsh
set ::CLIFF_ROOT [file normalize [file join [file dirname [info script]] ..]]
source [file join $::CLIFF_ROOT lib cliff main.tcl]
::cliff::main::dispatch $argv
```

Make executable:

```bash
chmod +x bin/cliff
```

- [ ] **Step 2: Implement main dispatcher**

`lib/cliff/main.tcl`:

```tcl
namespace eval ::cliff::main {
    proc dispatch {argv} {
        if {[llength $argv] < 1} { usage; exit 2 }
        set cmd [lindex $argv 0]
        set rest [lrange $argv 1 end]
        set cmdfile [file join $::CLIFF_ROOT lib cliff commands $cmd.tcl]
        if {![file exists $cmdfile]} {
            puts stderr "cliff: unknown subcommand: $cmd"
            usage
            exit 2
        }
        source [file join $::CLIFF_ROOT lib cliff profile.tcl]
        source [file join $::CLIFF_ROOT lib cliff validate.tcl]
        source [file join $::CLIFF_ROOT lib cliff docker.tcl]
        source $cmdfile
        ::cliff::cmd::$cmd $rest
    }
    proc usage {} {
        puts stderr "usage: cliff <run|exec|list|describe|sessions|session> \[args...\]"
    }
}
```

- [ ] **Step 3: Implement `list`**

`lib/cliff/commands/list.tcl`:

```tcl
namespace eval ::cliff::cmd {
    proc list {argv} {
        set pdir [file join $::CLIFF_ROOT profiles]
        foreach f [lsort [glob -nocomplain -directory $pdir *.tcl]] {
            set name [file rootname [file tail $f]]
            set prof [cliff::profile::load_file $f]
            set desc ""
            if {[dict exists $prof describe]} { set desc [dict get $prof describe] }
            set img ""
            if {[dict exists $prof image]} { set img [dict get $prof image] }
            puts [format "%-20s %-50s %s" $name $desc $img]
        }
    }
}
```

- [ ] **Step 4: Implement `describe`**

`lib/cliff/commands/describe.tcl`:

```tcl
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
```

- [ ] **Step 5: Create minimal test profile and smoke-test**

Create `profiles/base.tcl`:

```tcl
describe "Floor profile: tmpfs home, no creds, no egress"
image    cliff-base:0.2.0

workspace mode=ro
home      mode=tmpfs size=256m

limits { cpus 1; memory 1g; pids 256 }
```

Run:

```bash
./bin/cliff list
./bin/cliff describe base
```

Expected output includes `base  Floor profile: tmpfs home, no creds, no egress  cliff-base:0.2.0` and a dict-dump of the resolved profile.

- [ ] **Step 6: Commit**

```bash
git add bin/cliff lib/cliff/main.tcl lib/cliff/commands/list.tcl \
        lib/cliff/commands/describe.tcl profiles/base.tcl
git commit -m "cliff: main dispatcher + list and describe subcommands"
```

---

## Phase 6: Egress container image

### Task 9: Generate cliff CA

**Files:**
- Create: `images/ca/generate.sh`

- [ ] **Step 1: Write CA generation script**

`images/ca/generate.sh`:

```bash
#!/bin/sh
set -eu
DIR=$(dirname "$0")
if [ -f "$DIR/cliff-egress.crt" ] && [ -f "$DIR/cliff-egress.key" ]; then
    echo "CA already present; delete files to regenerate"; exit 0
fi
openssl req -x509 -newkey rsa:4096 -nodes \
    -keyout "$DIR/cliff-egress.key" \
    -out "$DIR/cliff-egress.crt" \
    -days 3650 \
    -subj "/CN=cliff-egress-ca" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"
chmod 600 "$DIR/cliff-egress.key"
echo "Generated $DIR/cliff-egress.{crt,key}"
```

```bash
chmod +x images/ca/generate.sh
./images/ca/generate.sh
```

- [ ] **Step 2: Verify outputs**

```bash
openssl x509 -in images/ca/cliff-egress.crt -noout -subject
```

Expected: `subject=CN = cliff-egress-ca`.

- [ ] **Step 3: Commit cert but not key**

`.gitignore` already excludes the key (Task 1).

```bash
git add images/ca/generate.sh images/ca/cliff-egress.crt
git commit -m "images/ca: cliff-egress CA generation + checked-in cert"
```

### Task 10: Egress container image

**Files:**
- Create: `images/egress/Dockerfile`
- Create: `images/egress/entrypoint.sh`
- Create: `images/egress/mitmproxy-addon.py`

- [ ] **Step 1: Write mitmproxy addon**

`images/egress/mitmproxy-addon.py`:

```python
"""Cliff egress addon: enforce host:port allowlist from $CLIFF_ALLOWLIST."""
import os
import fnmatch
from mitmproxy import http, ctx

def load_allowlist():
    raw = os.environ.get("CLIFF_ALLOWLIST", "")
    entries = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        host, _, port = line.rpartition(":")
        entries.append((host, int(port)))
    return entries

ALLOW = load_allowlist()

def _allowed(host: str, port: int) -> bool:
    return any(fnmatch.fnmatch(host, h) and p == port for h, p in ALLOW)

def http_connect(flow: http.HTTPFlow):
    host = flow.request.host
    port = flow.request.port
    if not _allowed(host, port):
        ctx.log.warn(f"DENY CONNECT {host}:{port}")
        flow.response = http.Response.make(403, b"cliff egress: host not allowlisted")
        return
    ctx.log.info(f"ALLOW CONNECT {host}:{port}")

def request(flow: http.HTTPFlow):
    host = flow.request.host
    port = flow.request.port
    if not _allowed(host, port):
        ctx.log.warn(f"DENY {flow.request.method} {host}:{port}{flow.request.path}")
        flow.response = http.Response.make(403, b"cliff egress: host not allowlisted")
        return
    ctx.log.info(f"ALLOW {flow.request.method} {host}:{port}{flow.request.path}")
```

- [ ] **Step 2: Write entrypoint**

`images/egress/entrypoint.sh`:

```sh
#!/bin/sh
set -eu

: "${CLIFF_ALLOWLIST:=}"  # newline-separated host:port patterns

# Render dnsmasq config: real resolution for allowlisted hosts, 127.0.0.1 for everything else.
cat > /etc/dnsmasq.conf <<EOF
no-hosts
no-resolv
server=1.1.1.1
server=8.8.8.8
address=/#/127.0.0.1
EOF

echo "$CLIFF_ALLOWLIST" | while IFS= read -r line; do
    [ -z "$line" ] && continue
    host="${line%:*}"
    # Let dnsmasq resolve allowlisted hosts normally
    printf 'server=/%s/1.1.1.1\n' "$host" >> /etc/dnsmasq.conf
done

dnsmasq -k &
exec mitmdump --mode regular@3128 \
    --set confdir=/etc/mitmproxy \
    -s /opt/cliff/mitmproxy-addon.py
```

- [ ] **Step 3: Write Dockerfile**

`images/egress/Dockerfile`:

```dockerfile
FROM alpine:3.19

RUN apk add --no-cache dnsmasq py3-pip ca-certificates \
 && pip3 install --break-system-packages mitmproxy==10.2.*

RUN mkdir -p /etc/mitmproxy /opt/cliff

# Bake cliff CA so app containers trust the egress proxy
COPY images/ca/cliff-egress.crt /etc/mitmproxy/mitmproxy-ca-cert.pem
COPY images/ca/cliff-egress.key /etc/mitmproxy/mitmproxy-ca.pem
RUN cat /etc/mitmproxy/mitmproxy-ca.pem /etc/mitmproxy/mitmproxy-ca-cert.pem \
    > /etc/mitmproxy/mitmproxy-ca-combined.pem

COPY images/egress/mitmproxy-addon.py /opt/cliff/mitmproxy-addon.py
COPY images/egress/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3128 53/udp
ENTRYPOINT ["/entrypoint.sh"]
```

- [ ] **Step 4: Add Makefile target**

Append to `Makefile`:

```makefile
build-egress:
	docker build -f images/egress/Dockerfile -t cliff-egress:0.3.0 .
```

- [ ] **Step 5: Build and smoke-test**

```bash
make build-egress
docker run --rm -e CLIFF_ALLOWLIST=$'example.com:443\nregistry-1.docker.io:443' cliff-egress:0.3.0 &
# Ctrl-C after confirming "HTTP(S) proxy listening at *:3128" prints
```

- [ ] **Step 6: Commit**

```bash
git add images/egress/ Makefile
git commit -m "egress: mitmproxy + dnsmasq sidecar image with allowlist enforcement"
```

### Task 11: Bake CA cert into cliff-base image

**Files:**
- Modify: `build/Dockerfile.base`

- [ ] **Step 1: Add CA to base image**

Insert into `build/Dockerfile.base` after the `apk add ca-certificates` line (or add the apk line if absent):

```dockerfile
# Install cliff-egress CA so mitmproxy-intercepted TLS is trusted inside containers.
COPY images/ca/cliff-egress.crt /usr/local/share/ca-certificates/cliff-egress.crt
RUN update-ca-certificates
```

- [ ] **Step 2: Rebuild base**

```bash
make build-base
```

- [ ] **Step 3: Verify**

```bash
docker run --rm cliff-base:0.3.0 sh -c 'awk "/cliff-egress/,/END CERT/" /etc/ssl/certs/ca-certificates.crt | head -1'
```

Expected: `-----BEGIN CERTIFICATE-----` (CA is concatenated into the system bundle).

- [ ] **Step 4: Bump Makefile tag constants if versioned. Rebuild dev/obsv/full to inherit.**

```bash
make build-all
```

- [ ] **Step 5: Commit**

```bash
git add build/Dockerfile.base
git commit -m "base: bake cliff-egress CA for TLS inspection by egress sidecar"
```

---

## Phase 7: Session lifecycle (integration)

### Task 12: Session ID + session dir

**Files:**
- Create: `lib/cliff/session.tcl`
- Create: `test/unit/session_id_test.tcl`

- [ ] **Step 1: Write failing test**

`test/unit/session_id_test.tcl`:

```tcl
package require tcltest
namespace import ::tcltest::*
source [file join [file dirname [info script]] .. .. lib cliff session.tcl]

test session-id-format {id is 6+ hex chars} -body {
    regexp {^[0-9a-f]{6,}$} [cliff::session::new_id base]
} -result 1

test session-id-unique {two IDs differ} -body {
    set a [cliff::session::new_id base]
    after 10
    set b [cliff::session::new_id base]
    expr {$a ne $b}
} -result 1

cleanupTests
```

- [ ] **Step 2: Run — expect failures**

Run: `tclsh test/unit/all.tcl`
Expected: FAIL.

- [ ] **Step 3: Implement**

`lib/cliff/session.tcl`:

```tcl
package require sha256 ;# from tcllib; if not available, fallback via exec sha256sum

namespace eval ::cliff::session {
    proc new_id {profile} {
        set seed "[clock microseconds]-$profile-[pid]-[expr {rand()}]"
        if {[catch {package present sha256}]} {
            set id [string range [exec sh -c "echo -n '$seed' | sha256sum" 0 11]]
        } else {
            set id [string range [::sha2::sha256 -hex $seed] 0 11]
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
```

- [ ] **Step 4: Run — expect pass**

Run: `tclsh test/unit/all.tcl`
Expected: PASS (25/25).

- [ ] **Step 5: Commit**

```bash
git add lib/cliff/session.tcl test/unit/session_id_test.tcl
git commit -m "session: ID generation and per-session state directory"
```

### Task 13: Egress allowlist rendering

**Files:**
- Create: `lib/cliff/egress.tcl`
- Create: `test/unit/egress_render_test.tcl`

- [ ] **Step 1: Write failing test**

`test/unit/egress_render_test.tcl`:

```tcl
package require tcltest
namespace import ::tcltest::*
source [file join [file dirname [info script]] .. .. lib cliff egress.tcl]

test egress-render-joins-allowlist {joins allow entries with newlines} -body {
    cliff::egress::render_allowlist {foo.com:443 bar.com:443}
} -result "foo.com:443\nbar.com:443"

test egress-render-empty {empty list yields empty string} -body {
    cliff::egress::render_allowlist {}
} -result ""

cleanupTests
```

- [ ] **Step 2: Run — expect failures**

Run: `tclsh test/unit/all.tcl`

- [ ] **Step 3: Implement**

`lib/cliff/egress.tcl`:

```tcl
namespace eval ::cliff::egress {
    proc render_allowlist {entries} {
        return [join $entries "\n"]
    }
    proc needs_sidecar {profile} {
        return [expr {[dict exists $profile egress allow] \
                      && [llength [dict get $profile egress allow]] > 0}]
    }
}
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git add lib/cliff/egress.tcl test/unit/egress_render_test.tcl
git commit -m "egress: render profile allowlist to newline-separated env format"
```

### Task 14: Cred-helper invocation

**Files:**
- Create: `lib/cliff/creds.tcl`
- Create: `helpers/none.tcl` (built-in no-op for testing)

- [ ] **Step 1: Implement cred helper invocation**

`lib/cliff/creds.tcl`:

```tcl
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
```

- [ ] **Step 2: Create the trivial test helper**

`helpers/none.tcl`:

```tcl
#!/usr/bin/env tclsh
# Outputs nothing; used by profiles that want to exercise the creds pipeline with no real cred.
exit 0
```

- [ ] **Step 3: Commit**

```bash
git add lib/cliff/creds.tcl helpers/none.tcl
git commit -m "creds: materialize scoped creds via host-side helper scripts"
```

### Task 15: Session runner — wire it all together

**Files:**
- Modify: `lib/cliff/session.tcl`
- Create: `lib/cliff/commands/run.tcl`
- Create: `lib/cliff/commands/exec.tcl`

- [ ] **Step 1: Add session start/stop to `lib/cliff/session.tcl`**

Append to `lib/cliff/session.tcl`:

```tcl
namespace eval ::cliff::session {
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
                --cap-drop ALL --cap-add NET_BIND_SERVICE \
                --security-opt no-new-privileges \
                -e CLIFF_ALLOWLIST=$allowlist \
                cliff-egress:0.3.0]
        }

        # Build app-container argv
        set command $A(command)
        if {$command eq ""} { set command {/bin/sh -l} }
        set argv [cliff::docker::build_argv \
            session_id $id \
            profile $profile \
            project $A(project) \
            command $command]

        # Inject egress env + creds
        if {$need_egress} {
            # Proxy the app container through the egress sidecar
            lappend argv \
                --dns cliff-egress-$id \
                --env http_proxy=http://cliff-egress-$id:3128 \
                --env https_proxy=http://cliff-egress-$id:3128 \
                --env HTTP_PROXY=http://cliff-egress-$id:3128 \
                --env HTTPS_PROXY=http://cliff-egress-$id:3128
        }

        # Replace --rm and -i with -it if interactive
        if {$A(interactive)} {
            set idx [lsearch $argv "-i"]
            set argv [lreplace $argv $idx $idx -it]
        }

        # After-start: write creds into container tmpfs
        # (exec docker run, then docker cp stdin into /run/creds — done via helper below)

        set exit_code 0
        if {[catch {
            # For creds, start detached, cp files, then attach or exec. For v1 simplicity we
            # pass creds as inline env only if helper outputs a single line; file-form creds
            # require detached-start path (see Task 16).
            exec {*}$argv >@stdout 2>@stderr <@stdin
        } err]} {
            set exit_code 1
            puts stderr "cliff: session $id failed: $err"
        }

        # Teardown
        if {$need_egress} {
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
```

- [ ] **Step 2: Implement `cliff run`**

`lib/cliff/commands/run.tcl`:

```tcl
source [file join $::CLIFF_ROOT lib cliff session.tcl]
source [file join $::CLIFF_ROOT lib cliff creds.tcl]
source [file join $::CLIFF_ROOT lib cliff egress.tcl]

namespace eval ::cliff::cmd {
    proc run {argv} {
        if {[llength $argv] < 1} { error "usage: cliff run <profile> \[--project=<path>\]" }
        set profile [lindex $argv 0]
        set project ""
        foreach a [lrange $argv 1 end] {
            if {[regexp {^--project=(.+)$} $a -> v]} { set project $v }
        }
        exit [cliff::session::run $profile project $project interactive 1]
    }
}
```

- [ ] **Step 3: Implement `cliff exec`**

`lib/cliff/commands/exec.tcl`:

```tcl
source [file join $::CLIFF_ROOT lib cliff session.tcl]
source [file join $::CLIFF_ROOT lib cliff creds.tcl]
source [file join $::CLIFF_ROOT lib cliff egress.tcl]

namespace eval ::cliff::cmd {
    proc exec {argv} {
        if {[llength $argv] < 3} { error "usage: cliff exec <profile> --project=<path> -- <cmd...>" }
        set profile [lindex $argv 0]
        set project ""
        set command ""
        set i 1
        while {$i < [llength $argv]} {
            set a [lindex $argv $i]
            if {[regexp {^--project=(.+)$} $a -> v]} { set project $v; incr i }\
            elseif {$a eq "--"} { set command [lrange $argv [expr {$i+1}] end]; break }\
            else { incr i }
        }
        exit [cliff::session::run $profile project $project command $command interactive 0]
    }
}
```

- [ ] **Step 4: Smoke test end-to-end (offline profile only; egress path exercised in Phase 8)**

Create minimal test profile `profiles/dev-offline.tcl`:

```tcl
inherit base
describe "Dev image, offline"
image    cliff-dev:0.3.0
workspace mode=rw
```

Run:

```bash
mkdir -p /tmp/cliff-smoke && echo hello > /tmp/cliff-smoke/file
./bin/cliff exec dev-offline --project=/tmp/cliff-smoke -- cat /workspace/file
```

Expected: prints `hello`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add lib/cliff/session.tcl lib/cliff/commands/run.tcl lib/cliff/commands/exec.tcl \
        profiles/dev-offline.tcl
git commit -m "session: wire profile → docker; cliff run + exec subcommands"
```

### Task 16: Credential injection via detached-start + docker cp

The inline-exec approach in Task 15 cannot write cred files into the container's tmpfs before the shell starts. We need a two-stage start: `docker create`, write creds to `/run/creds/`, then `docker start -ai`.

**Files:**
- Modify: `lib/cliff/session.tcl`

- [ ] **Step 1: Refactor session::run for detached start**

Replace the session execution block in `lib/cliff/session.tcl` with:

```tcl
        # Replace: exec {*}$argv ...
        # With: docker create → docker cp creds → docker start -ai

        # Replace `docker run --rm -i` with `docker create -i --name ...`
        set create_argv $argv
        set create_argv [lreplace $create_argv 0 2 docker create]
        # remove --rm (not valid with create; we clean up manually)
        set idx [lsearch $create_argv "--rm"]
        if {$idx >= 0} { set create_argv [lreplace $create_argv $idx $idx] }

        set container_id [exec {*}$create_argv]

        # Write creds into /run/creds
        dict for {name bytes} $creds {
            set tmp [file tempfile tmp_path]
            puts -nonewline $tmp $bytes
            close $tmp
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
```

- [ ] **Step 2: Smoke-test again**

```bash
./bin/cliff exec dev-offline --project=/tmp/cliff-smoke -- cat /workspace/file
```

Expected: still prints `hello`.

- [ ] **Step 3: Commit**

```bash
git add lib/cliff/session.tcl
git commit -m "session: two-stage start lets creds materialize in tmpfs before shell"
```

---

## Phase 8: Profile set

### Task 17: Ship the v0.3.0 profile set

**Files:**
- Create: `profiles/yolo-dev.tcl`
- Create: `profiles/dev-aws-read.tcl`, `profiles/dev-aws-write.tcl`
- Create: `profiles/obsv-local.tcl`
- Create: `helpers/aws-sts.tcl`

- [ ] **Step 1: `profiles/yolo-dev.tcl`**

```tcl
inherit base
describe "Dev image, writable workspace, no creds, egress to package registries only"
image    cliff-dev:0.3.0
workspace mode=rw
home      mode=tmpfs size=512m

egress {
    allow registry-1.docker.io:443
    allow registry.terraform.io:443
    allow pypi.org:443
    allow files.pythonhosted.org:443
    allow dl-cdn.alpinelinux.org:443
}

limits { cpus 2; memory 4g; pids 512 }
```

- [ ] **Step 2: `profiles/dev-aws-read.tcl`**

```tcl
inherit base
describe "Dev image, read-only AWS creds via STS, egress to AWS endpoints"
image    cliff-dev:0.3.0
workspace mode=rw
home      mode=tmpfs size=512m

creds {
    aws helper=aws-sts args={role=READ_ROLE_ARN ttl=3600}
}

egress {
    allow *.amazonaws.com:443
    allow *.s3.amazonaws.com:443
}

limits { cpus 2; memory 4g; pids 512 }

env {
    AWS_SHARED_CREDENTIALS_FILE /run/creds/aws
    AWS_REGION us-east-1
}
```

- [ ] **Step 3: `profiles/dev-aws-write.tcl`**

Same as `dev-aws-read.tcl` but swap describe text and `role=WRITE_ROLE_ARN` — leaves the role ARN as a placeholder the user must replace locally (documented in README).

```tcl
inherit base
describe "Dev image, write-capable AWS creds via STS, egress to AWS endpoints"
image    cliff-dev:0.3.0
workspace mode=rw
home      mode=tmpfs size=512m

creds {
    aws helper=aws-sts args={role=WRITE_ROLE_ARN ttl=3600}
}

egress {
    allow *.amazonaws.com:443
    allow *.s3.amazonaws.com:443
}

limits { cpus 2; memory 4g; pids 512 }

env {
    AWS_SHARED_CREDENTIALS_FILE /run/creds/aws
    AWS_REGION us-east-1
}
```

- [ ] **Step 4: `profiles/obsv-local.tcl`**

```tcl
inherit base
describe "Observability tools, workspace read-only, egress to localhost only"
image    cliff-obsv:0.3.0
workspace mode=ro

# No egress allow entries → --network none; localhost inside container is the container itself.
# For talking to host grafana, user runs grafana inside this container via local CLI tools.

limits { cpus 1; memory 2g; pids 256 }
```

- [ ] **Step 5: `helpers/aws-sts.tcl`**

```tcl
#!/usr/bin/env tclsh
# aws-sts: calls `aws sts assume-role` using host default creds, emits a credentials file
# (INI format) on stdout suitable for AWS_SHARED_CREDENTIALS_FILE.
#
# Args: role=ARN ttl=SECONDS

if {$::argc < 1} {
    puts stderr "aws-sts: expected args 'role=ARN ttl=SECONDS'"; exit 2
}
foreach pair [lindex $::argv 0] {
    if {[regexp {^([^=]+)=(.*)$} $pair -> k v]} { set kv($k) $v }
}
if {![info exists kv(role)] || ![info exists kv(ttl)]} {
    puts stderr "aws-sts: missing role= or ttl="; exit 2
}

set json [exec aws sts assume-role \
    --role-arn $kv(role) \
    --role-session-name cliff-$::env(USER)-[clock seconds] \
    --duration-seconds $kv(ttl)]

# Parse JSON minimally — we only need three fields.
foreach key {AccessKeyId SecretAccessKey SessionToken} {
    if {[regexp "\"$key\"\\s*:\\s*\"(\[^\"]+)\"" $json -> val]} { set c($key) $val }
}
puts "\[default\]"
puts "aws_access_key_id = $c(AccessKeyId)"
puts "aws_secret_access_key = $c(SecretAccessKey)"
puts "aws_session_token = $c(SessionToken)"
```

```bash
chmod +x helpers/aws-sts.tcl
```

- [ ] **Step 6: Verify `cliff list` shows all profiles**

```bash
./bin/cliff list
```

Expected: 6 lines (base, dev-offline, dev-aws-read, dev-aws-write, obsv-local, yolo-dev).

- [ ] **Step 7: Commit**

```bash
git add profiles/ helpers/aws-sts.tcl
git commit -m "profiles: ship base, dev-offline, dev-aws-{read,write}, obsv-local, yolo-dev"
```

---

## Phase 9: Sessions observability

### Task 18: `cliff sessions` and `cliff session <id>`

**Files:**
- Create: `lib/cliff/commands/sessions.tcl`
- Create: `lib/cliff/commands/session.tcl`

- [ ] **Step 1: Implement `sessions`**

`lib/cliff/commands/sessions.tcl`:

```tcl
namespace eval ::cliff::cmd {
    proc sessions {argv} {
        set base [file join $::env(HOME) .local share cliff sessions]
        if {![file exists $base]} { return }
        foreach d [lsort [glob -nocomplain -directory $base -type d *]] {
            set id [file tail $d]
            set exit_code "?"
            if {[file exists [file join $d exit]]} {
                set fh [open [file join $d exit] r]; set exit_code [string trim [read $fh]]; close $fh
            }
            set when [clock format [file mtime $d] -format {%Y-%m-%d %H:%M}]
            puts [format "%s  %s  exit=%s" $id $when $exit_code]
        }
    }
}
```

- [ ] **Step 2: Implement `session`**

`lib/cliff/commands/session.tcl`:

```tcl
namespace eval ::cliff::cmd {
    proc session {argv} {
        if {[llength $argv] != 1} { error "usage: cliff session <id>" }
        set id [lindex $argv 0]
        set d [file join $::env(HOME) .local share cliff sessions $id]
        if {![file isdirectory $d]} { error "no such session: $id" }
        foreach f {profile.tcl exit egress.log} {
            set p [file join $d $f]
            if {[file exists $p]} {
                puts "=== $f ==="
                set fh [open $p r]; puts [read $fh]; close $fh
            }
        }
    }
}
```

- [ ] **Step 3: Smoke test**

```bash
./bin/cliff sessions
./bin/cliff session <id-from-above-list>
```

Expected: lists recent sessions; dumps resolved profile + exit code for the named session.

- [ ] **Step 4: Commit**

```bash
git add lib/cliff/commands/sessions.tcl lib/cliff/commands/session.tcl
git commit -m "cliff: sessions + session <id> observability subcommands"
```

### Task 19: Wire egress log into session dir

**Files:**
- Modify: `lib/cliff/session.tcl`

- [ ] **Step 1: Mount session dir into egress container and set log destination**

In `lib/cliff/session.tcl`, modify the egress container start so mitmproxy logs land in the session dir. Replace the egress `docker run` with:

```tcl
            set egress_cid [exec docker run -d \
                --name cliff-egress-$id \
                --network cliff-$id \
                --read-only \
                --tmpfs /tmp --tmpfs /var \
                --cap-drop ALL --cap-add NET_BIND_SERVICE \
                --security-opt no-new-privileges \
                -e CLIFF_ALLOWLIST=$allowlist \
                -v $sdir:/var/log/cliff:rw \
                cliff-egress:0.3.0]
```

Modify `images/egress/entrypoint.sh` to redirect mitmdump output:

Replace `exec mitmdump ...` with:

```sh
exec mitmdump --mode regular@3128 \
    --set confdir=/etc/mitmproxy \
    -s /opt/cliff/mitmproxy-addon.py \
    2>&1 | tee -a /var/log/cliff/egress.log
```

- [ ] **Step 2: Rebuild egress image**

```bash
make build-egress
```

- [ ] **Step 3: Run a session with egress and verify log is written**

```bash
./bin/cliff exec yolo-dev --project=/tmp/cliff-smoke -- sh -c 'wget -q -O- https://registry.terraform.io/.well-known/terraform.json || true'
cat ~/.local/share/cliff/sessions/*/egress.log | tail -5
```

Expected: at least one `ALLOW` or `DENY` line.

- [ ] **Step 4: Commit**

```bash
git add lib/cliff/session.tcl images/egress/entrypoint.sh
git commit -m "session: persist egress log to session dir"
```

---

## Phase 10: Sandbox enforcement integration tests

### Task 20: Test harness

**Files:**
- Create: `test/integration/harness.sh`

- [ ] **Step 1: Write shared helpers**

`test/integration/harness.sh`:

```bash
#!/bin/bash
# Sourced by each enforcement test.
set -eu
CLIFF="${CLIFF:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/cliff}"
FIXDIR="$(mktemp -d)"
trap 'rm -rf "$FIXDIR"' EXIT

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }
assert_exit() {
    local want=$1; shift
    local got
    set +e
    "$@" >/dev/null 2>&1
    got=$?
    set -e
    if [ "$got" -ne "$want" ]; then
        fail "expected exit $want, got $got: $*"
    fi
}
```

- [ ] **Step 2: Commit**

```bash
git add test/integration/harness.sh
chmod +x test/integration/harness.sh
git commit -m "test: integration harness helpers"
```

### Task 21: Filesystem enforcement test

**Files:**
- Create: `test/integration/enforcement_fs.sh`

- [ ] **Step 1: Write test**

`test/integration/enforcement_fs.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/harness.sh"

# Workspace read-only: writes to /workspace under an ro profile fail.
echo "seed" > "$FIXDIR/file"
set +e
"$CLIFF" exec obsv-local --project="$FIXDIR" -- sh -c 'echo mutate > /workspace/file'
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "workspace ro: write should have failed, rc=$rc"
grep -q "^seed$" "$FIXDIR/file" || fail "workspace ro: fixture mutated"
pass "workspace ro mount rejects writes"

# Persistence: home is tmpfs — files don't survive across sessions.
"$CLIFF" exec dev-offline --project="$FIXDIR" -- sh -c 'touch /home/devuser/marker'
if "$CLIFF" exec dev-offline --project="$FIXDIR" -- sh -c 'test -f /home/devuser/marker'; then
    fail "home persisted across sessions"
fi
pass "home tmpfs is ephemeral"

# Read-only rootfs: writes to /etc fail.
set +e
"$CLIFF" exec dev-offline --project="$FIXDIR" -- sh -c 'touch /etc/should-not-exist'
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "read-only rootfs: /etc write should have failed"
pass "rootfs is read-only"

echo "enforcement_fs: all passed"
```

- [ ] **Step 2: Run**

```bash
chmod +x test/integration/enforcement_fs.sh
./test/integration/enforcement_fs.sh
```

Expected: 3 PASS lines, exit 0.

- [ ] **Step 3: Commit**

```bash
git add test/integration/enforcement_fs.sh
git commit -m "test: fs enforcement — ro workspace, tmpfs home, ro rootfs"
```

### Task 22: Network enforcement test

**Files:**
- Create: `test/integration/enforcement_net.sh`

- [ ] **Step 1: Write test**

`test/integration/enforcement_net.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/harness.sh"

# Offline profile: no network at all
set +e
"$CLIFF" exec dev-offline --project="$FIXDIR" -- sh -c 'wget -q -T 3 -O- https://example.com'
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "dev-offline reached example.com"
pass "dev-offline has no network"

# Yolo-dev: registries allowed, other hosts blocked
set +e
"$CLIFF" exec yolo-dev --project="$FIXDIR" -- sh -c 'wget -q -T 5 -O- https://example.com'
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "yolo-dev reached example.com (should be blocked)"
pass "yolo-dev blocks non-allowlisted host"

# Allowlisted: should succeed
"$CLIFF" exec yolo-dev --project="$FIXDIR" -- sh -c 'wget -q -T 10 -O- https://registry.terraform.io/.well-known/terraform.json' \
    || fail "yolo-dev could not reach allowlisted registry.terraform.io"
pass "yolo-dev allows registry.terraform.io"

# DNS: non-allowlisted names resolve to 127.0.0.1
"$CLIFF" exec yolo-dev --project="$FIXDIR" -- sh -c '
    addr=$(nslookup example.com 2>/dev/null | awk "/^Address: /{print \$2; exit}")
    [ "$addr" = "127.0.0.1" ] || exit 1
' || fail "DNS: non-allowlisted name did not return 127.0.0.1"
pass "DNS: non-allowlisted names return 127.0.0.1"

echo "enforcement_net: all passed"
```

- [ ] **Step 2: Run**

```bash
chmod +x test/integration/enforcement_net.sh
./test/integration/enforcement_net.sh
```

Expected: 4 PASS.

- [ ] **Step 3: Commit**

```bash
git add test/integration/enforcement_net.sh
git commit -m "test: network enforcement — offline, allowlist, DNS 127.0.0.1"
```

### Task 23: Credential enforcement test

**Files:**
- Create: `test/integration/enforcement_creds.sh`

- [ ] **Step 1: Write test**

`test/integration/enforcement_creds.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/harness.sh"

# No host cred directory ever appears in a container
set +e
"$CLIFF" exec dev-offline --project="$FIXDIR" -- sh -c 'ls /host 2>/dev/null; test -e /host'
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "/host is visible in container"
pass "/host not mounted"

# No ~/.aws in any profile without creds
"$CLIFF" exec yolo-dev --project="$FIXDIR" -- sh -c '
    test ! -e /home/devuser/.aws
' || fail "yolo-dev has ~/.aws (should not)"
pass "yolo-dev has no AWS creds"

# /run/creds exists but is empty for no-creds profile
"$CLIFF" exec yolo-dev --project="$FIXDIR" -- sh -c '
    test -d /run/creds && [ -z "$(ls -A /run/creds)" ]
' || fail "/run/creds not empty for yolo-dev"
pass "/run/creds is empty absent cred declarations"

echo "enforcement_creds: all passed"
```

- [ ] **Step 2: Run**

```bash
chmod +x test/integration/enforcement_creds.sh
./test/integration/enforcement_creds.sh
```

- [ ] **Step 3: Commit**

```bash
git add test/integration/enforcement_creds.sh
git commit -m "test: creds enforcement — host dirs invisible, tmpfs empty when absent"
```

### Task 24: Resource-limit enforcement test

**Files:**
- Create: `test/integration/enforcement_limits.sh`

- [ ] **Step 1: Write test**

`test/integration/enforcement_limits.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/harness.sh"

# Fork bomb hits pids limit (yolo-dev is 512)
set +e
timeout 10 "$CLIFF" exec yolo-dev --project="$FIXDIR" -- sh -c '
    i=0
    while [ $i -lt 2000 ]; do
        sh -c "sleep 30" &
        i=$((i+1))
    done
'
rc=$?
set -e
# Expect non-zero (hit limit or timed out)
[ "$rc" -ne 0 ] || fail "fork bomb unrestricted"
pass "pids limit caps process count"

# Non-root uid
uid=$("$CLIFF" exec yolo-dev --project="$FIXDIR" -- id -u)
[ "$uid" != "0" ] || fail "container running as root"
pass "container runs as non-root"

echo "enforcement_limits: all passed"
```

- [ ] **Step 2: Run + commit**

```bash
chmod +x test/integration/enforcement_limits.sh
./test/integration/enforcement_limits.sh
git add test/integration/enforcement_limits.sh
git commit -m "test: resource limits — pids capped, non-root uid"
```

### Task 25: Lifecycle test — list/describe/sessions

**Files:**
- Create: `test/integration/lifecycle.sh`

- [ ] **Step 1: Write**

`test/integration/lifecycle.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/harness.sh"

"$CLIFF" list | grep -q "^base " || fail "list did not include base"
pass "cliff list"

"$CLIFF" describe base | grep -q "image: cliff-base" || fail "describe base malformed"
pass "cliff describe"

"$CLIFF" exec dev-offline --project="$FIXDIR" -- true
sid=$("$CLIFF" sessions | tail -1 | awk '{print $1}')
[ -n "$sid" ] || fail "no session id captured"
"$CLIFF" session "$sid" | grep -q "=== profile.tcl ===" || fail "session <id> missing sections"
pass "cliff sessions + session <id>"

echo "lifecycle: all passed"
```

- [ ] **Step 2: Run + commit**

```bash
chmod +x test/integration/lifecycle.sh
./test/integration/lifecycle.sh
git add test/integration/lifecycle.sh
git commit -m "test: lifecycle — list, describe, sessions, session <id>"
```

### Task 26: Makefile targets for the test suites

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Append targets**

```makefile
test-unit:
	tclsh test/unit/all.tcl

test-integration: build-all build-egress
	./test/integration/enforcement_fs.sh
	./test/integration/enforcement_net.sh
	./test/integration/enforcement_creds.sh
	./test/integration/enforcement_limits.sh
	./test/integration/lifecycle.sh

test-sandbox: test-unit test-integration
```

- [ ] **Step 2: Run**

```bash
make test-sandbox
```

Expected: unit passes (25+), integration passes (~15 PASS lines).

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "make: test-unit, test-integration, test-sandbox aggregate targets"
```

---

## Phase 11: Documentation

### Task 27: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add `## Cliff CLI` section before the existing `## Building` section**

Insert:

```markdown
## Cliff CLI (v0.3.0)

`bin/cliff` launches hardened, profile-driven, ephemeral container sessions safe for LLM
use. Each session runs under a profile declaring image, mount posture, credentials, egress
allowlist, and resource limits. Credentials are minted on the host and written to a
container-private tmpfs; egress (if any) is proxied through a per-session mitmproxy sidecar
enforcing the profile's allowlist; hostnames outside the allowlist resolve to 127.0.0.1.

### Quick start

```bash
bin/cliff list                                          # show profiles
bin/cliff describe yolo-dev                             # show resolved profile
bin/cliff run yolo-dev --project=$PWD                   # interactive shell
bin/cliff exec yolo-dev --project=$PWD -- terraform init # one-shot command
bin/cliff sessions                                      # recent sessions
bin/cliff session <id>                                  # session detail
```

### Profiles shipped

| Profile | Image | Workspace | Creds | Egress |
|---|---|---|---|---|
| `base` | cliff-base | ro | none | none |
| `dev-offline` | cliff-dev | rw | none | none |
| `yolo-dev` | cliff-dev | rw | none | package registries |
| `dev-aws-read` | cliff-dev | rw | STS read role | `*.amazonaws.com` |
| `dev-aws-write` | cliff-dev | rw | STS write role | `*.amazonaws.com` |
| `obsv-local` | cliff-obsv | ro | none | none |

Replace `READ_ROLE_ARN` / `WRITE_ROLE_ARN` in the AWS profiles with your account's role ARNs
before using.

### For LLMs

Expose `bin/cliff` on PATH. In project-level `CLAUDE.md` (or equivalent), add:

> For any infrastructure command (terraform, kubectl, aws, helm, etc.), invoke via
> `cliff exec <profile> --project=<path> -- <cmd>`. Do not run these tools directly on the
> host. See `cliff list` for available profiles.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: document cliff CLI, profiles, LLM integration pattern"
```

### Task 28: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Replace "Current State" block**

Change the `## Current State` section to:

```markdown
## Current State (as of 2026-04-17)

**v0.3.0 — in progress.** LLM sandbox wrapper (`bin/cliff`) with profile-driven, ephemeral,
hardened container sessions. See `docs/superpowers/specs/2026-04-17-cliff-llm-sandbox-design.md`
and `docs/superpowers/plans/2026-04-17-cliff-llm-sandbox.md`.

**v0.2.0 — shipped.** All package versions refreshed.

**v0.1.0 — shipped.** 4 Docker images built, tested, published to ghcr.io/imsmith.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: CLAUDE.md reflects v0.3.0 in progress"
```

---

## Self-Review Checklist (performed during plan authoring; verified inline)

**Spec coverage:**
- Architecture → Tasks 8, 15, 16 (main dispatcher + session runner).
- Profile model (inheritance, wholesale replacement) → Tasks 2–5.
- Credential injection (tmpfs, cred-helper, no host mounts) → Tasks 14, 16.
- Egress (mitmproxy, cliff CA, pi-hole DNS, no escape hatch) → Tasks 9, 10, 11, 13, 19.
- Session semantics (read-only rootfs, tmpfs home, no volumes, ephemeral) → Task 7 argv + Task 15 session; enforced by integration Task 21.
- LLM surface (`cliff exec`, profile discovery) → Tasks 8, 15, 18, 27.
- Testing (per-threat enforcement tests, no goblin test) → Tasks 20–26.

**Placeholder scan:** `READ_ROLE_ARN` / `WRITE_ROLE_ARN` are deliberate user-editable placeholders in shipped profiles, not plan placeholders; documented in README. No other TBDs or "add appropriate error handling"-style hand-waves.

**Type consistency:**
- `cliff::session::run` signature used consistently in Tasks 15 and 16.
- Profile dict shape (`image`, `workspace.mode`, `home.mode`/`home.size`, `egress.allow`/`egress.deny`, `limits.cpus`/`limits.memory`/`limits.pids`, `env.*`, `creds.<name>.helper`/`args`) is consistent across profile parser (Tasks 2–4), validator (Task 6), docker argv (Task 7), session (Task 15).
- `cliff-egress:0.3.0` tag used consistently in Tasks 10, 15, 19.
- `/run/creds` path consistent (Tasks 7, 16, 23).

**Open implementation items** flagged in the spec are resolved in-plan:
- Profile-parser sandbox: safe slave interp (Task 2).
- Docker stance: rootful on Linux, confirmed in prose.
- Dropped caps: `--cap-drop ALL` baseline (Task 7); egress sidecar adds `NET_BIND_SERVICE` (Task 15).
- Helper stdout contract: raw bytes, written to `/run/creds/<name>` verbatim (Task 16); `aws-sts` emits INI format (Task 17).
- `cliff describe` output: resolved dict dump plus name comment (Task 8).

---

## Execution

Plan complete and saved to `docs/superpowers/plans/2026-04-17-cliff-llm-sandbox.md`.

Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — I execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
