ui = true

# good untill single instance vault server. Acceptable for learning purposes
# storage "inmem" {}

backend "consul" {
  path          = "vault/"
  address       = "IP_ADDRESS:8500"
  cluster_addr  = "https://IP_ADDRESS:8201"
  redirect_addr = "http://IP_ADDRESS:8200"
  token         = "CONSUL_TOKEN"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "IP_ADDRESS:8201"
  tls_disable     = 1
}
