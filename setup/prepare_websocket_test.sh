#!/usr/bin/env bash
source init.sh

yellow "Building websocket-test..."
_IMAGE="futuswarm-websocket-test"
_NAME="websocket-test"
rm -rf /tmp/$_NAME
cp -R ../$_NAME /tmp/$_NAME/
cd /tmp/$_NAME
git init . 1>/dev/null
git add -A 1>/dev/null
git commit -m "all in" 1>/dev/null
_TAG="${_TAG:-$(git rev-parse --short HEAD)}"
docker build -t "$_IMAGE:$_TAG" . 1>/dev/null
cd - 1>/dev/null

cd ../client
yellow "Pushing $_NAME image to Swarm..."
( SU=true \
    . ./cli.sh image:push -i "$_IMAGE" -t "$_TAG" )

deploy_service $_IMAGE $_TAG $_NAME 1>/dev/null &
spinner $! "Deploying $_IMAGE:$_TAG as $_NAME"

cd - 1>/dev/null
