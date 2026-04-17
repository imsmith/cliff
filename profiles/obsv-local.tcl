inherit base
describe "Observability tools, workspace read-only, egress to localhost only"
image    cliff-obsv:0.3.0
workspace mode=ro

limits { cpus 1; memory 2g; pids 256 }
