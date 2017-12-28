#!/usr/bin/env bash
source init.sh

# ACL for CLI commands
ACL_DB_NAME="${ACL_DB_NAME:-}"
_RDS_USER="${RDS_USER:-}"
_RDS_PASS="${RDS_PASS:-}"
_RDS_HOST="${RDS_HOST:-$(rds_db_host $RDS_NAME)}"
_RDS_PORT="${RDS_PORT:-}"
if [ -z "$_RDS_USER" ] || [ -z "$_RDS_PASS" ] || [ -z "$_RDS_HOST" ] || [ -z "$_RDS_PORT" ]; then
    red "RDS_USER/RDS_PASS/RDS_HOST/RDS_PORT unset"
    exit 1
fi

# futuswarm DB for ACL
# db: futuswarm_internal
SCHEMA="CREATE TABLE acl (id serial, username text NOT NULL, service text NOT NULL, PRIMARY KEY (id), UNIQUE (username, service));"

REMOTE=$(cat <<EOF
PGPASSWORD='$_RDS_PASS' psql -h "$_RDS_HOST" -p "$_RDS_PORT" -U "$_RDS_USER" postgres -c "create database $ACL_DB_NAME;"
EOF
)
R="$(run_sudo $HOST "$REMOTE" 2>&1)"

REMOTE=$(cat <<EOF
PGPASSWORD='$_RDS_PASS' psql -h "$_RDS_HOST" -p "$_RDS_PORT" -U "$_RDS_USER" "$ACL_DB_NAME" -c "$SCHEMA"
EOF
)
R="$(run_sudo $HOST "$REMOTE" 2>&1)"

# exit 0 for tests
echo -n
