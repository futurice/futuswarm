# Futuswarm Installation

## Local Configuration

Requirements:
 * Docker (eg. [Docker for Mac](https://docs.docker.com/docker-for-mac/))
 * AWS CLI `pip install awscli`

Configure administrator AWS details and credentials [IAM#users](https://console.aws.amazon.com/iam/home?#/users), eg:

* ~/.aws/credentials

    ```bash
    [futuswarm]
    aws_access_key_id =
    aws_secret_access_key =
    ```

* ~/.aws/config

    ```bash
    [profile futuswarm]
    output = json
    region = eu-central-1
    ```

## Futuswarm Configuration

Choose a NAME -- all lowercase characters (used for settings directory, AWS resource naming, domains). Prepare your shell environment, to have access to the functions used in the examples, with the following commands:

```sh
cd setup/
source commands.sh
mk_cloud NAME
```

The above initializes your futuswarm with `mk_cloud NAME`. This copies configuration files to the `config/NAME` directory, as later on referred to by the `CLOUD=NAME` variable.

## Installer

The installation script configures futuswarm as described in [docs/index.md](index.md). The installer can and should be run multiple times (resources are created only once, then updated on any changes). It is recommended to run the installer twice to get a clean overview/log of the installation, which is especially helpful for troubleshooting typical initial configuration issues related to DNS and SSL certificates.

```sh
CLOUD= \
    AWS_PROFILE=futuswarm \
    RDS_USER=master \
    RDS_PASS=secret \
    ./install.sh \
    --aws-key= \
    --aws-secret= \
    --registry-user= \
    --registry-pass=
```

Where
 * `aws-key` and `aws-secret` are AWS administrator credentials
 * `registry-user` and `registry-pass` are Docker Hub credentials (private registry and image backups).
 * (optional) `--vault-pass=`: `vault-pass` is an Ansible password used for SSSD installation (central SSH authentication via LDAP).
 * (optional) `--use-sssd`: Auth via LDAP using SSSD
 * (optional) CONFIG_DIR= path to settings directory

### Futuswarm shell functions

With the cloud initialized it can be used directly in the future with the following shell environment configuration:

```sh
cd setup/
export CLOUD=NAME
export AWS_PROFILE=futuswarm
source init.sh
```

A few useful functions:
 * `node_list` list all swarm instance public IPs
 * `loginto IP` access an instance as admin using keys generated during installation
 * `manager_ip` public IP of the swarm manager

Notes:
 * Add `export CONFIG_DIR=` to point to an external `config/` directory to keep the futuswarm repository clean.

### Configuration state and intended usage

The installer is best for creating an immutable cloud. It should be run multiple times for small adjustments with red/green checks signalling the state of the system.
 * On major changes: Change `CLOUD` for a completely new standalone installation with a clear migration path (recommended)
 * On minor changes: Change `TAG` for modifying current installation with sweeping changes, or modify individual settings for fine-grained control

Known things that are out of scope:
 * firewall port changes

### SSL certificates

The ELB's SSL certificate is by default requested from [ACM](https://aws.amazon.com/certificate-manager/). Check confirmation email to activate domains.

### AWS configuration

The SSH key to access instances configured from:
  * Configure EC2 Key Pair (EC2 > Network & Security > Key Pairs > Create Key Pair)

### DNS

Configure the nameserver to point our `{{DOMAIN}}` (see settings) to the ELB address.

```sh
echo $(proxy_elb "$ELB_NAME"|proxy_ip) # Gives {{PROXY_IP}}
```

```sh
$ORIGIN {{DOMAIN}}.
@                       IN CNAME {{PROXY_IP}}.
*                       IN CNAME {{PROXY_IP}}.
```

### Futuswarm CLI

Allows all specified users (and groups when using SSSD) to use the Swarm directly given they have an SSH key configured.

The CLI is downloadable from `cli_location`. Welcome instructions at `echo https://futuswarm.$DOMAIN`.

As admin, add yourself and others (non-SSSD setup) with their SSH public keys. Assumes CLI downloaded as 'futuswarm':
`SU=true SSH_USER=ubuntu SSH_KEY=$SSH_KEY futuswarm admin:user:add --user $USER --key $HOME/.ssh/id_rsa.pub`

Get started: `futuswarm app:deploy -i nginx -n my-nginx-server`


