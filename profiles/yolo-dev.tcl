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
