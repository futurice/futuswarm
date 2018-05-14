#!/usr/bin/env bash
RUN_ID="${RUN_ID:-$RANDOM}"
TERM="${TERM:-xterm-256color}"
PYTHON_BIN="${PYTHON_BIN:-python}"

MODENV="${MODENV:-y}"
STRICT="${STRICT:-n}"
if [ "$MODENV" == "y" ]; then
    if [ "$STRICT" == "y" ]; then
        set -u -e -o pipefail
    else
        set -u +e +o pipefail
    fi
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CDIR="$DIR"
source $DIR/commands.sh

CLOUD="${CLOUD:=}"
if [ -z "$CLOUD" ]; then
    echo "CLOUD= is undefined"
    safe_exit
else
    DEFAULT_CONFIG_DIR="$DIR/../config/"
    CDIR_BASE="${CONFIG_DIR:-$DEFAULT_CONFIG_DIR}"
    CDIR="${CDIR_BASE}${CLOUD}"
    source $CDIR/settings.sh
fi
source $DIR/aws.sh
source $DIR/aws_instances.sh

CLI_DIR="$DIR/../client"
FUTUSWARM_SERVICE_DIR="$DIR/../container"
FUTUSWARM_HEALTH_DIR="$DIR/../container/health"
