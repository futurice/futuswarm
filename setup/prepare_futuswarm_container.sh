#!/usr/bin/env bash
source init.sh

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CLI_NAME="${_CLI_NAME:-$CLI_NAME}"
HOST="${HOST:-$(manager_ip)}"

# Prepare "Hello World" container
set +u # virtualenv...
mk_virtualenv
source venv/bin/activate

rm -rf /tmp/container
# defaults
cp -R ../container /tmp/container
# CONFIG_DIR overrides
if [ -d "$CDIR/container/" ]; then
    cp $CDIR/container/* /tmp/container/
fi

# Customize futuswarm
replaceinfile '/tmp/container/index.md' 'CLI_LOCATION' "$(cli_location)"
replaceinfile '/tmp/container/index.md' 'CLI_NAME' "$CLI_NAME"
replaceinfile '/tmp/container/index.md' 'COMPANY' "$COMPANY"
replaceinfile '/tmp/container/index.md' 'OPEN_DOMAIN' "$OPEN_DOMAIN"

# .md -> .html
markdown2 /tmp/container/index.md > /tmp/container/index.html

mv /tmp/container/index.html /tmp/container/index.html_
HEADER=$(cat <<EOF
<html>
<head
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1"/>
<link href="https://fonts.googleapis.com/css?family=Work+Sans:400,600" rel="stylesheet">
<link rel="stylesheet" href="index.css"/>
</head>
<body>
 <div class="container">
EOF
)

FOOTER=$(cat <<EOF
 </div>
</body>
</html>
EOF
)

FS="futuswarm"
cd /tmp/container
cat <(echo "$HEADER") index.html_ > index.html_2
cat <(echo "$FOOTER") index.html_2 >> index.html
git init . 1>/dev/null
git add -A 1>/dev/null
git commit -am "-.-" 1>/dev/null
TAG=$(git rev-parse --short HEAD)
docker build -t $FS:$TAG . 1> /dev/null
cd - 1>/dev/null

push_image $FS $TAG

cd ../client
deploy_service $FS $TAG $FS 1>/dev/null &
spinner $! "Deploying $FS:$TAG as mainpage"
cd - 1>/dev/null

# exit virtualenv
deactivate
set -u
