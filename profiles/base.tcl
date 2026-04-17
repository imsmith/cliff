describe "Floor profile: tmpfs home, no creds, no egress"
image    cliff-base:0.3.0

workspace mode=ro
home      mode=tmpfs size=256m

limits { cpus 1; memory 1g; pids 256 }
