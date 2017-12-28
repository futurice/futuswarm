#!/usr/bin/env bats

source setup/commands.sh

@test "lineinfile" {
    F=/tmp/f
    S="my-str"
    lineinfile $S $F
    result="$(grep $S $F)"
    [ "$result" == "$S" ]
    rm $F
}

@test "replaceOrAppendInFile" {
    F=/tmp/f
    touch $F
    S="ExecStart=/usr/bin/docker $F"
    replaceOrAppendInFile $F '^ExecStart=.*' "$S"
    result=$(cat $F)
    [ "$result" == "$S" ]
    replaceOrAppendInFile $F '^ExecStart=.*' "$S"
    result="$(cat $F)"
    [ "$result" == "$S" ]
    rm $F
}

@test "replaceOrAppendInFileWhenCommented" {
    F=/tmp/f2
    touch $F
    S="ExecStart=/usr/bin/docker $F"
    echo "#$S">$F
    replaceOrAppendInFile $F '^#ExecStart=.*' "$S"
    result=$(cat $F)
    [ "$result" == "$S" ]
    rm $F
}

@test "contains_str" {
    F=/tmp/f
    S="hello-world"
    echo $S > $F
    file_contains_str $F $S
    [ $? -eq 0 ]
    rm $F
}

@test "test '--name=john'" {
    R=$(arg_required name "--name=john" "--port")
    [ "$R" = "john" ]
}

@test "test '--name john'" {
    R=$(arg_required "name" "--name" "john")
    [ "$R" = "john" ]
}

@test "test '-n john'" {
    R=$(arg_required "name" "-n" "john")
    [ "$R" = "john" ]
}

@test "json parse non-existing entry" {
    run bash -c "echo {}|jq -r '.action // empty'"
    [ "$output" = "" ]

    run bash -c "echo {}|jq -r '.action'"
    [ "$output" = "null" ]
}

@test "json parse existing empty entry" {
    run bash -c "echo '{\"action\":\"\"}'|jq -r '.action // empty'"
    [ "$output" = "" ]

    run bash -c "echo '{\"action\":\"\"}'|jq -r '.action'"
    [ "$output" = "" ]
}
