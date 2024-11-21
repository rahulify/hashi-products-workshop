# Packer variables (all are required)
region                    = "us-east-1"

# Terraform variables (all are required)
ami                       = "ami-01368679adfbf0c8b"

# These variables will default to the values shown
# and do not need to be updated unless you want to
# change them
allowlist_ip            = "0.0.0.0/0"
name_prefix             = "nomad_offsite"
server_instance_type    = "t2.large"
server_count            = "1"
client_instance_type    = "t2.large"
client_count            = "2"