# Installation

These instructions are for creating a Docker Swarm cluster.

https://docs.docker.com/engine/swarm/

## Architecture Notes

Request life cycle:
```sh
HTTP(s) request towards https://service-name.cloud.company.com
 => AWS Elastic Load Balancer (ACM certificate, HTTPS termination)
 => Single Sign-On (SSO) via Apache
 => Service Discovery via Docker Flow Proxy (Golang server to HAProxy)
 => Application Service
```

Deployed services are accessible and configurable using the CLI by their deployment name (`-n name`).

SSSD (optional) allows SSH access to the servers for client-server CLI interaction with the swarm.

Links:
[mod_auth_pubtkt](https://neon1.net/mod_auth_pubtkt/)
[Docker Flow Proxy](https://github.com/vfarcic/docker-flow-proxy)
[SSSD](https://github.com/futurice/ansible)

## Local Configuration

Requirements:
 * Docker installation (eg. [Docker for Mac](https://docs.docker.com/docker-for-mac/))
 * AWS CLI `pip install awscli`

Configure administrator AWS credentials.

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

## Services Configuration for a new cluster

Prepare initial configuration with `mk_cloud NAME`. This copies configuration files to the config/NAME
directory that are used with when referring to the `CLOUD=` variable.

```sh
cd setup/
source commands.sh
mk_cloud NAME
```

## Using local shell functions

```sh
cd setup/
export CLOUD=
export AWS_PROFILE=futuswarm
source init.sh
```

A few useful functions:
 * `node_list` list all swarm instance public IPs
 * `loginto IP` access an instance as admin using keys generated during installation
 * `manager_ip` public IP of the swarm manager

## Install

The installation script provides a minimum configuration state to run the Swarm. Can be run multiple times.
It is recommended to run the installer twice to get a clean overview of the setup.

```sh
CLOUD= \
    AWS_PROFILE=futuswarm \
    RDS_USER=master \
    RDS_PASS='my-secret-password' \
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

### Configuration State and intended usage

The installer is best for creating an immutable cloud. It can be run multiple times for small adjustments
with red/green checks signalling the state of the system.

On bigger changes increment `TAG` (and modify any settings) to a fresh installation and update DNS records to point to the new cloud.

Known things that are out of scope:
 * firewall port changes

### SSL certificates

The ELB's SSL certificate can be obtained from ACM

AWS ACM (https://aws.amazon.com/certificate-manager/)
- Check confirmation email to activate domain

### AWS configuration

The SSH key to access instances configured from:
  * Configure EC2 Key Pair (EC2 > Network & Security > Key Pairs > Create Key Pair)

### DNS

Configure the nameserver to point our `{{DOMAIN}}` (see settings) to the Elastic Load Balancer address.

```sh
proxy_elb|proxy_ip # {{PROXY_IP}}
```

```sh
$ORIGIN {{DOMAIN}}.
@                       IN CNAME {{PROXY_IP}}.
*                       IN CNAME {{PROXY_IP}}.
```

### PaaS CLI

Allows all specified users (and groups when using SSSD) to use the Swarm directly given they have an SSH key configured.

The CLI is downloadable from `cli_location`.

As admin, add yourself and others (non-SSSD setup) with their SSH public keys. Assumes CLI downloaded as 'futuswarm':
`SU=true SSH_USER=ubuntu SSH_KEY=$SSH_KEY futuswarm admin:user:add --user $USER --key $HOME/.ssh/id_rsa.pub`

Get started: `futuswarm app:deploy -i nginx -n my-nginx-server`


