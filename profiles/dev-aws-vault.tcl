inherit base
describe "Dev image, AWS creds snapshotted from aws-vault, egress to AWS endpoints"
image    cliff-dev:0.3.0
workspace mode=rw
home      mode=tmpfs size=512m

# Snapshot creds from the host's aws-vault. No AWS CLI required on host.
# Creds expire mid-session if you exceed the role's session duration —
# this is intentional (circuit breaker for exploratory work).
creds {
    aws helper=aws-vault args={profile=kata duration=14400}
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
