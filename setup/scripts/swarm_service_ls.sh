#!/usr/bin/env bash
KEY="$1"
S=$(docker service ls --format '{{json .}}')
C=$(secret get $KEY)
if [[ "$S" != "$C" ]]; then
  secret put $KEY "$S"
fi
