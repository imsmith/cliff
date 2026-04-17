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
