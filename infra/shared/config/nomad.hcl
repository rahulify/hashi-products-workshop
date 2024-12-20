data_dir  = "/opt/nomad/data"
bind_addr = "0.0.0.0"

# Enable the server
server {
  enabled          = true
  bootstrap_expect = SERVER_COUNT
}

consul {
  address = "127.0.0.1:8500"
  token = "CONSUL_TOKEN"
}

acl {
  enabled = true
}

vault {
  enabled          = true
  address          = "http://127.0.0.1:8200"
  task_token_ttl   = "1h"
  create_from_role = "nomad-cluster"
  token            = "VAULT_USER_TOKEN"
}

