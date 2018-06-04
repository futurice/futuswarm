#!/usr/bin/env bash
source init.sh

# HOSTS=ip ip2 ip3
HOSTS="$HOSTS"
# VAULT_PASS=x
VAULT_PASS="$VAULT_PASS"

# prepare machines for Ansible
# - keeps root access for ubuntu intact for rest of the scripts to work with AWS AMI
# 1: ip
sssd_prep() {
REMOTE=$(cat <<EOF
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update
apt-get -qq install -o=Dpkg::Use-Pty=0 -y python python2.7 python2.7-dev
EOF
)
run_sudo "$1" "$REMOTE"
}

for ip in ${HOSTS[@]}; do
    sssd_prep "$ip" &
done
wait $(jobs -p)

# ensure clean tmp-directory
rm -rf /tmp/ansible

mk_virtualenv
source_virtualenv

if [ ! -d /tmp/ansible ]; then
git clone git@github.com:futurice/ansible.git /tmp/ansible 1>/dev/null||true
fi

cd /tmp/ansible/

replaceinfile '/tmp/ansible/roles/sssd/templates/sssd.conf.j2' '^ldap_uri =.*' "ldap_uri = $LDAP_SSSD_SERVER"
replaceinfile '/tmp/ansible/roles/sssd/templates/sssd.conf.j2' '^ldap_tls_reqcert =.*' "ldap_tls_reqcert = $LDAP_SSSD_REQCERT"
replaceinfile '/tmp/ansible/roles/sssd/templates/sssd.conf.j2' '^ldap_id_use_start_tls =.*' "ldap_id_use_start_tls = $LDAP_SSSD_TLS"
# fix for slow logins
replaceOrAppendInFile '/tmp/ansible/roles/sssd/templates/sssd.conf.j2' '^ignore_group_members =.*' "ignore_group_members = true"

echo "[tag_sssd_yes]" > swarm_hosts.ini
echo "$HOSTS"|tr " " "\n" >> swarm_hosts.ini
echo "$VAULT_PASS" > vault_pass.txt

install_sssd() {
ANSIBLE_STDOUT_CALLBACK=actionable ansible-playbook site.yml -i swarm_hosts.ini --tags "sssd" -u $SSH_USER --private-key "$SSH_KEY"
}

install_sssd
# install_sssd 1>/dev/null &
# spinner $! "Processing Ansible instructions..."

deactivate_virtualenv
cd - 1>/dev/null

# TODO: "${0##*/}" in subshell points to parent
do_post_install "prepare_sssd.sh"

sssd_up() {
IS_RUNNING=$(run_sudo $1 "is_running sssd")
rg_status "$IS_RUNNING" "$1: SSSD is running"
}
for ip in ${HOSTS[@]}; do
    sssd_up "$ip" &
done
wait $(jobs -p)
