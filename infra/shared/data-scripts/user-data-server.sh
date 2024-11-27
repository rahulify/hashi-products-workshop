#!/bin/bash

set -e

exec > >(sudo tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
sudo bash /ops/shared/scripts/server.sh "${cloud_env}" "${server_count}" '${retry_join}' "${nomad_binary}"

ACL_DIRECTORY="/ops/shared/config"
CONSUL_BOOTSTRAP_TOKEN="/tmp/consul_bootstrap"
NOMAD_BOOTSTRAP_TOKEN="/tmp/nomad_bootstrap"
NOMAD_USER_TOKEN="/tmp/nomad_user_token"

sed -i "s/CONSUL_TOKEN/${nomad_consul_token_secret}/g" /etc/nomad.d/nomad.hcl
sed -i "s/CONSUL_TOKEN/${nomad_consul_token_secret}/g" /etc/vault.d/vault.hcl

sudo systemctl restart nomad

echo "Finished server setup"

echo "ACL bootstrap begin"

# Wait until leader has been elected and bootstrap consul ACLs
for i in {1..9}; do
    # capture stdout and stderr
    set +e
    sleep 5
    OUTPUT=$(consul acl bootstrap 2>&1)
    if [ $? -ne 0 ]; then
        echo "consul acl bootstrap: $OUTPUT"
        if [[ "$OUTPUT" = *"No cluster leader"* ]]; then
            echo "consul no cluster leader"
            continue
        else
            echo "consul already bootstrapped"
            exit 0
        fi

    fi
    set -e

    echo "$OUTPUT" | grep -i secretid | awk '{print $2}' > $CONSUL_BOOTSTRAP_TOKEN
    if [ -s $CONSUL_BOOTSTRAP_TOKEN ]; then
        echo "consul bootstrapped"
        break
    fi
done


consul acl policy create -name 'nomad-auto-join' -rules="@$ACL_DIRECTORY/consul-acl-nomad-auto-join.hcl" -token-file=$CONSUL_BOOTSTRAP_TOKEN

consul acl role create -name "nomad-auto-join" -description "Role with policies necessary for nomad servers and clients to auto-join via Consul." -policy-name "nomad-auto-join" -token-file=$CONSUL_BOOTSTRAP_TOKEN

consul acl token create -accessor=${nomad_consul_token_id} -secret=${nomad_consul_token_secret} -description "Nomad server/client auto-join token" -role-name nomad-auto-join -token-file=$CONSUL_BOOTSTRAP_TOKEN

# Wait for nomad servers to come up and bootstrap nomad ACL
for i in {1..12}; do
    # capture stdout and stderr
    set +e
    sleep 5
    OUTPUT=$(nomad acl bootstrap 2>&1)
    if [ $? -ne 0 ]; then
        echo "nomad acl bootstrap: $OUTPUT"
        if [[ "$OUTPUT" = *"No cluster leader"* ]]; then
            echo "nomad no cluster leader"
            continue
        else
            echo "nomad already bootstrapped"
            exit 0
        fi
    fi
    set -e

    echo "$OUTPUT" | grep -i secret | awk -F '=' '{print $2}' | xargs | awk 'NF' > $NOMAD_BOOTSTRAP_TOKEN
    if [ -s $NOMAD_BOOTSTRAP_TOKEN ]; then
        echo "nomad bootstrapped"
        break
    fi
done

nomad acl policy apply -token "$(cat $NOMAD_BOOTSTRAP_TOKEN)" -description "Policy to allow reading of agents and nodes and listing and submitting jobs in all namespaces." node-read-job-submit $ACL_DIRECTORY/nomad-acl-user.hcl

nomad acl token create -token "$(cat $NOMAD_BOOTSTRAP_TOKEN)" -name "read-token" -policy node-read-job-submit | grep -i secret | awk -F "=" '{print $2}' | xargs > $NOMAD_USER_TOKEN

# Write user token to kv
consul kv put -token-file=$CONSUL_BOOTSTRAP_TOKEN nomad_user_token "$(cat $NOMAD_USER_TOKEN)"

echo "ACL bootstrap end"

# After consul bootstrap is completed, vault shall consume the consul as its storage.
sudo systemctl restart vault

sleep 10

export VAULT_ADDR=http://127.0.0.1:8200
echo "export VAULT_ADDR=http://127.0.0.1:8200" >> ~/.bashrc

touch /etc/vault.d/init.file
vault operator init > /etc/vault.d/init.file

echo -e '\e[38;5;198m'"++++ Auto unseal vault"

for i in $(cat /etc/vault.d/init.file | grep Unseal | cut -d " " -f4 | head -n 3); do vault operator unseal $i; done
VAULT_ROOT_TOKEN=$(grep 'Initial Root Token' /etc/vault.d/init.file | cut -d ':' -f2 | tr -d ' ')

consul kv put -token-file=$CONSUL_BOOTSTRAP_TOKEN vault_token "$VAULT_ROOT_TOKEN"

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

vault login $VAULT_ROOT_TOKEN

vault policy write nomad-server nomad-server-policy.hcl

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

vault write /auth/token/roles/nomad-cluster @nomad-cluster-role.json

tee access-tables-policy.hcl <<EOF
path "database/creds/accessdb" {
  capabilities = ["read"]
}
EOF

vault policy write access-tables access-tables-policy.hcl

vault token create -policy nomad-server -period 72h -orphan