# hashi-products-workshop
The repository help to setup a Coffee ordering portal using Hashi stack

## ENV
```sh
export AWS_ACCESS_KEY_ID=<from doormat>
export AWS_SECRET_ACCESS_KEY==<from doormat>
export AWS_SESSION_TOKEN=<from doormat>

export HCP_CLIENT_ID=<from HCP project level SP>
export HCP_CLIENT_SECRET=<from HCP project level SP>
```

## Build

```sh
packer init -var-file=variables.hcl image.pkr.hcl
packer build -var-file=variables.hcl image.pkr.hcl

terraform apply -var-file=variables.hcl
```

## Unsel Vault
```sh
sudo systemctl restart vault
export VAULT_ADDR=http://127.0.0.1:8200
vault operator init
```

```txt
$ vault operator init
Unseal Key 1: REDACTED
Unseal Key 2: REDACTED
Unseal Key 3: REDACTED
Unseal Key 4: REDACTED
Unseal Key 5: REDACTED

Initial Root Token: <VAULT_ROOT_TOKEN>
```

```sh
vault operator unseal <unseal key#1>
vault operator unseal <unseal key#2>
vault operator unseal <unseal key#3>
```


```sh
export VAULT_TOKEN='<VAULT_ROOT_TOKEN>'
vault secrets enable database
> Success! Enabled the database secrets engine at: database/
```

```sh
tee nomad-server-policy.hcl <<EOF

# Allow creating tokens under "nomad-cluster" token role. The token role name
# should be updated if "nomad-cluster" is not used.
path "auth/token/create/nomad-cluster" {
  capabilities = ["update"]
}

# Allow looking up "nomad-cluster" token role. The token role name should be
# updated if "nomad-cluster" is not used.
path "auth/token/roles/nomad-cluster" {
  capabilities = ["read"]
}

# Allow looking up the token passed to Nomad to validate # the token has the
# proper capabilities. This is provided by the "default" policy.
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Allow looking up incoming tokens to validate they have permissions to access
# the tokens they are requesting. This is only required if
# `allow_unauthenticated` is set to false.
path "auth/token/lookup" {
  capabilities = ["update"]
}

# Allow revoking tokens that should no longer exist. This allows revoking
# tokens for dead tasks.
path "auth/token/revoke-accessor" {
  capabilities = ["update"]
}

# Allow checking the capabilities of our own token. This is used to validate the
# token upon startup.
path "sys/capabilities-self" {
  capabilities = ["update"]
}

# Allow our own token to be renewed.
path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF
```

```sh
$ vault policy write nomad-server nomad-server-policy.hcl
> Success! Uploaded policy: nomad-server
```

```sh
tee nomad-cluster-role.json <<EOF
{
  "allowed_policies": "access-tables",
  "token_explicit_max_ttl": 0,
  "name": "nomad-cluster",
  "orphan": true,
  "token_period": 259200,
  "renewable": true
}
EOF
```

```sh
$ vault write /auth/token/roles/nomad-cluster @nomad-cluster-role.json
> Success! Data written to: auth/token/roles/nomad-cluster
```

```sh
tee access-tables-policy.hcl <<EOF
path "database/creds/accessdb" {
  capabilities = ["read"]
}
EOF
```

```sh
$ vault policy write access-tables access-tables-policy.hcl
Success! Uploaded policy: access-tables
```

```sh
$ vault token create -policy nomad-server -period 72h -orphan
Key                  Value
---                  -----
token                <VAULT_USER_TOKEN>
token_accessor       tITkxcf084q2WWRFtNsKKkcv
token_duration       72h
token_renewable      true
token_policies       ["default" "nomad-server"]
identity_policies    []
policies             ["default" "nomad-server"]
```

The `VAULT_USER_TOKEN` is needed to be provided in nomad server configuartion in `vault` block

```hcl
vault {
  enabled          = true
  address          = "http://127.0.0.1:8200"
  task_token_ttl   = "1h"
  create_from_role = "nomad-cluster"
  token            = "VAULT_USER_TOKEN"
}
```