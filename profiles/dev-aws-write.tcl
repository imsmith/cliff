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
