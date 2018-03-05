# !/usr/bin/env bats
source test_init.sh

# https://github.com/sstephenson/bats
# for debugging, use in unit tests:
# echo "status = ${status}"
# echo "output = ${output}"

@test "Initialize" {
    # prepare environment
    ensure_container_running
}

_SECRETS_MOCK=$(cat <<EOF
{"DATABASE_URL":"postgresql://user:pass@hostname/db","DB_HOST":"dbhost-in-cloud-aws.com","DB_NAME":"futurice","SHOUT":"hello world=hello world"}
EOF
)
_SECRETS_MOCK_NOHEADER="$(echo "$_SECRETS_MOCK")"

_SERVICES_MOCK=$(cat <<EOF
{"ID":"foiir9nzulhl","Image":"nginx:latest","Mode":"replicated","Name":"nginx-test","Ports":"","Replicas":"1/1"}
{"ID":"whj7vdtcilw7","Image":"vfarcic/docker-flow-proxy:latest","Mode":"replicated","Name":"proxy","Ports":"*:81-\u003e80/tcp,*:444-\u003e443/tcp","Replicas":"1/1"}
{"ID":"foiir9nzulhl","Image":"mixman/http-hello:latest","Mode":"replicated","Name":"another-hello-test","Ports":"","Replicas":"1/1"}
EOF
)
_SERVICES_MOCK_NOHEADER="$(echo "$_SERVICES_MOCK")"

@test "Check /status page works" {
    run bash -c "curl -s localhost/status"
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "Check swarm internal networking health" {
    run bash -c "$(client) swarm:network:health|grep Healthy"
    result=$(echo -e "$output"|grep "Healthy")
    [ "$status" -eq 0 ]
}

# re-use a service for faster tests
SERVICE="test"
SERVICE_ONE="acl-multi-one"
SERVICE_TWO="acl-multi-two"
SERVICE_THREE="acl-multi-three"
@test "Test app:deploy" {
    run bash -c "$(client) app:deploy -n $SERVICE_ONE -i mixman/http-hello --async"
    run bash -c "$(client) app:deploy -n $SERVICE_TWO -i mixman/http-hello --async"
    run bash -c "$(client) app:deploy -n $SERVICE_THREE -i mixman/http-hello --async"
    run bash -c "$(client) app:deploy -n $SERVICE -i mixman/http-hello"
    [ "$status" -eq 0 ]
    run bash -c "docker service ps $SERVICE|sed 1d|head -n1"
    result=$(printf "$output"|grep -i "running")
    [ "$?" -eq 0 ]
}

@test "Test image:push" {
    run bash -c "docker pull alpine"
    run bash -c "$(client) image:push -i alpine"
    [ "$status" -eq 0 ]
}

@test "Test app:list contains docker-flow-swarm-listener" {
    run bash -c "$(client) app:list|grep vfarcic/docker-flow-swarm-listener"
    [ "$status" -eq 0 ]
}

@test "Test app:list contains docker-flow-proxy" {
    run bash -c "$(client) app:list|grep docker-flow-proxy"
    [ "$status" -eq 0 ]
}

@test "Test app:list contains sso-proxy" {
    run bash -c "$(client) app:list|grep futurice/sso-proxy"
    [ "$status" -eq 0 ]
}

@test "Test config, config:set, config:get, config, config:unset" {
    run bash -c "$(client) config:unset KEY -n $SERVICE --async"

    run bash -c "$(client) config -n $SERVICE"
    [ "$status" -eq 0 ]

    run bash -c "$(client) config:set KEY=avain -n $SERVICE --async"
    [ "$status" -eq 0 ]
    S="Success! Wrote: $SERVICE/default/KEY"
    result=$(echo -e "$output"|grep "$S")
    [ "$?" -eq 0 ]

    run bash -c "$(client) config:get KEY -n $SERVICE"
    [ "$status" -eq 0 ]
    result=$(echo -e "$output"|grep "avain")
    [ "$?" -eq 0 ]

    run bash -c "$(client) config -n $SERVICE|grep avain"
    [ "$status" -eq 0 ]

    run bash -c "$(client) config:unset KEY -n $SERVICE --async"
    [ "$status" -eq 0 ]
    S="Success! Deleted: $SERVICE/default/KEY"
    result=$(echo -e "$output"|grep "$S")
    [ "$?" -eq 0 ]

    run bash -c "$(client) config -n $SERVICE"
    [ "$status" -eq 0 ]
}

@test "Test config:set is applied to existing service environment" {
    run bash -c "$(client) config:set KEY=red KEY2=blue -n $SERVICE --async"
    [ "$status" -eq 0 ]

    run bash -c "docker service inspect $SERVICE|jq -r 'first|.Spec.TaskTemplate.ContainerSpec.Env|@csv'"
    # order is not quaranteed
    result=$(echo -e "$output"|grep "KEY=red")
    [ "$?" -eq 0 ]
    result=$(echo -e "$output"|grep "KEY2=blue")
    [ "$?" -eq 0 ]
}

@test "Test config is applied to new service" {
    run bash -c "$(client) config:set KEY3=green -n $SERVICE"
    [ "$status" -eq 0 ]

    run bash -c "docker service inspect $SERVICE|jq -r 'first|.Spec.TaskTemplate.ContainerSpec.Env|@csv'"
    result=$(echo -e "$output"|grep "KEY3=green")
    [ "$?" -eq 0 ]
}

@test "Test accessing a service and executing 'uname' command" {
    run bash -c "$(client) app:run --action uname -n $SERVICE"
    [ "$status" -eq 0 ]
    S="Linux"
    result=$(printf "$output"|grep "$S")
    [ "$?" -eq 0 ]
}

@test "Test accessing a service and executing 'ls -laF' command" {
    run bash -c "$(client) app:run --action \"ls -laF\" -n $SERVICE"
    [ "$status" -eq 0 ]
    result=$(printf "$output"|grep "proc/")
    [ "$?" -eq 0 ]
}

@test "Test deploying new tag for same service" {
    run bash -c "docker service ps $SERVICE|sed 1d|head -n1"
    result=$(printf "$output"|grep "mixman/http-hello:latest")
    [ "$?" -eq 0 ]
    run bash -c "$(client) app:deploy -i mixman/http-hello -n $SERVICE -t t2 --async"
    [ "$status" -eq 0 ]
    run bash -c "docker service ps $SERVICE|sed 1d|head -n1"
    result=$(printf "$output"|grep "mixman/http-hello:t2")
    [ "$?" -eq 0 ]
}

@test "Test deploying non-existing image" {
    run bash -c "$(client) app:deploy -i produce-of-developers-not-here -t foobar -n not-here-foo --async"
    S="forgot to image:push?"
    result=$(echo -e "$output"|grep "$S")
    [ "$?" -eq 0 ]
}

@test "Test db:postgres:create DB_URL is valid" {
    run bash -c "$(client) db:create:postgres -n $SERVICE"
    [ "$status" -eq 0 ]

    run bash -c "$(client) config:get DB_URL -n $SERVICE"
    [ "$status" -eq 0 ]

    DB_URL="$output"
    run bash -c "docker exec postgres psql $DB_URL -c \"\q\""
    [ "$status" -eq 0 ]
}

@test "Test acl:user:add, acl:user:list, acl:user:rm" {
    run bash -c "$(client) acl:user:list -n $SERVICE"
    [ "$status" -eq 0 ]
    result=$(printf "$output"|grep "client")
    [ "$?" -eq 0 ]

    run bash -c "$(client) acl:user:add john -n $SERVICE"
    [ "$status" -eq 0 ]
    result=$(printf "$output"|grep "added to")
    [ "$?" -eq 0 ]

    run bash -c "$(client) acl:user:list -n $SERVICE"
    R=$(nl_to_space "$output")
    [ "$status" -eq 0 ]
    result=$(printf "$R"|grep "john")
    [ "$?" -eq 0 ]

    run bash -c "$(client) acl:user:add mary -n $SERVICE"
    [ "$status" -eq 0 ]
    result=$(printf "$output"|grep "added to")
    [ "$?" -eq 0 ]

    run bash -c "$(client) acl:user:list -n $SERVICE"
    R=$(nl_to_space "$output")
    [ "$status" -eq 0 ]

    [ "$(is_in_list "mary" "$R")" == "y" ]
    [ "$(is_in_list "john" "$R")" == "y" ]
    [ "$(is_in_list "mario" "$R")" == "" ]

    result=$(printf "$R"|grep "john mary")
    [ "$?" -eq 0 ]

    run bash -c "$(client) acl:user:rm mary -n $SERVICE"
    [ "$status" -eq 0 ]
    result=$(printf "$output"|grep "removed from")
    [ "$?" -eq 0 ]

    run bash -c "$(client) acl:user:list -n $SERVICE"
    R=$(nl_to_space "$output")
    [ "$status" -eq 0 ]
    [ "$(is_in_list "mary" "$R")" == "" ]
}

@test "Test acl:user part of multiple services" {
    run bash -c "$(client) acl:user:add john -n $SERVICE_ONE"
    [ "$status" -eq 0 ]
    result=$(printf "$output"|grep "added to")
    [ "$?" -eq 0 ]

    run bash -c "$(client) acl:user:add john -n $SERVICE_TWO"
    [ "$status" -eq 0 ]
    result=$(printf "$output"|grep "added to")
    [ "$?" -eq 0 ]

    run bash -c "$(client) acl:user:add john -n $SERVICE_THREE"
    [ "$status" -eq 0 ]
    result=$(printf "$output"|grep "added to")
    [ "$?" -eq 0 ]

    run bash -c "$(client) acl:user:services john"
    R=$(nl_to_space "$output")
    [ "$status" -eq 0 ]
    [ "$(is_in_list "$SERVICE_ONE" "$R")" == "y" ]
    [ "$(is_in_list "$SERVICE_TWO" "$R")" == "y" ]
    [ "$(is_in_list "$SERVICE_THREE" "$R")" == "y" ]
    [ "$(is_in_list "tes" "$R")" == "" ]
}

@test "Test acl:user catches unauthorized user" {
    run bash -c "$(client "badclient") config -n $SERVICE"
    [ "$status" -eq 0 ]
    result=$(printf "$output"|grep "Unauthorized")
    [ "$?" -eq 0 ]
}

@test "Test user is added to their own service" {
    run bash -c "$(client) acl:user:list -n $SERVICE"
    R=$(nl_to_space "$output")
    [ "$status" -eq 0 ]
    [ "$(is_in_list "client" "$R")" == "y" ]
}

@test "Test admin can add user to service owned by non-admin" {
}

@test "Test '--extra=\"--mount type=volume,target=/data,source=play_hello_hello,volume-driver=rexray\"" {
    R=$(arg_required "extra" "--extra" "--mount type=volume,target=/data,source=play_hello_hello,volume-driver=rexray")
    [ "$R" = "--mount type=volume,target=/data,source=play_hello_hello,volume-driver=rexray" ]
}

@test "Test pulling image from private registry when image not pushed to swarm" {
    run bash -c "docker exec servers docker rmi $COMPANY/alpine:futuswarm"
    run bash -c "docker pull alpine; docker tag alpine $COMPANY/alpine:futuswarm; docker push $COMPANY/alpine:futuswarm"
    run bash -c "$(client) app:deploy -n alpine-private -i $COMPANY/alpine -t futuswarm --action 'ping localhost' --async"
    [ "$status" -eq 0 ]
    run bash -c "$(client) app:remove -n alpine-private"
}

@test "Test deploying a service that executes a command" {
    run bash -c "$(client) app:deploy -n alpine-ping -i alpine --action 'ping localhost' --async"
    [ "$status" -eq 0 ]
    run bash -c "$(client) app:remove -n alpine-ping"
}

@test "Test admin migrate-services" {
    run bash -c "cd setup/ && FROM_AWS_PROFILE=test CLOUD=test TO_AWS_PROFILE=test MOCK_SERVICES='$_SERVICES_MOCK_NOHEADER' bash admin.sh restore-services --to=/tmp/cli_local && cd -"
    [ "$status" -eq 0 ]
    SERVICE="another-hello-test"
    run bash -c "docker service ps $SERVICE --format '{{.Name}} {{.DesiredState}}'|head -n1"
    result=$(printf "$output"|grep "$SERVICE")
    [ "$?" -eq 0 ]
}

@test "Test admin migrate-secrets" {
    run bash -c "cd setup/ && FROM_AWS_PROFILE=test CLOUD=test TO_AWS_PROFILE=test MOCK_SECRETS='$_SECRETS_MOCK_NOHEADER' MOCK_SERVICES='$_SERVICES_MOCK_NOHEADER' bash admin.sh migrate-secrets --to=/tmp/cli_local && cd -"
    [ "$status" -eq 0 ]
    run bash -c "$(client) config:get DB_HOST -n another-hello-test"
    [ "$status" -eq 0 ]
    result=$(echo -e "$output"|grep "dbhost-in-cloud-aws")
    [ "$?" -eq 0 ]
}
