#!/usr/bin/env tclsh
# aws-vault: snapshot AWS credentials from `aws-vault` (99designs) at session
# start, emit an INI file on stdout for AWS_SHARED_CREDENTIALS_FILE.
#
# Args: profile=NAME [duration=SECONDS]
#
# Requires aws-vault on the host. Does NOT require the AWS CLI on the host.
# Creds are frozen for the session; they will expire mid-run if you exceed
# the role's session duration. That is intentional (circuit breaker).

if {$::argc < 1} {
    puts stderr "aws-vault: expected args 'profile=NAME \[duration=SECONDS\]'"
    exit 2
}
foreach pair [lindex $::argv 0] {
    if {[regexp {^([^=]+)=(.*)$} $pair -> k v]} { set kv($k) $v }
}
if {![info exists kv(profile)]} {
    puts stderr "aws-vault: missing profile="
    exit 2
}

set cmd [list aws-vault export --format=ini]
if {[info exists kv(duration)]} {
    lappend cmd --duration=$kv(duration)s
}
lappend cmd $kv(profile)

if {[catch {exec {*}$cmd} out err]} {
    puts stderr "aws-vault: export failed: $out"
    exit 1
}

# aws-vault --format=ini emits "[NAME]" headers (credentials-file syntax);
# rewrite the requested profile to "[default]" so AWS_SHARED_CREDENTIALS_FILE
# consumers pick it up without further configuration.
regsub -line "^\\\[$kv(profile)\\\]\$" $out "\[default\]" out
puts $out
