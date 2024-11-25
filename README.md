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

