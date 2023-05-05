#!/bin/bash
set -euo pipefail

#COMMIT=$(git rev-parse HEAD)
COMMIT=4083f7b1b8497c6eb1d6e9415787675513492328
REPO="https://github.com/apache/couchdb"

jq_opt() {
  case $1 in
  1)
    DESCRIPTION="Module couch_hash.erl: Enable FIPS mode at compile time or runtime"
    ;;
  2)
    DESCRIPTION="Comments and test cases etc"
    ;;
  esac
  jq -r --arg repo $REPO --arg digest $COMMIT --arg desc "$DESCRIPTION" '. | select(.type=="match") | {"uri": .data.path.text, "description": ($desc), "line": .data.line_number, "link": "\($repo)/blob/\($digest)/\(.data.path.text)#L\(.data.line_number)"}'
}

rg couch_hash:md5_hash -i -t erlang -t elixir --sort path --json | jq_opt 1
rg "md5[ |\-|,]" -i -t erlang -t elixir --sort path --json | jq_opt 2
