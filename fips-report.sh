#!/bin/bash
set -euo pipefail

COMMIT=$(git rev-parse HEAD)
VERSION=$(cat version.mk | tr -d '\n' | tr -dc '0-9' | sed 's/./\.&/g;s/.//')
print_only=false

gen_report() {
  echo "# FIPS: md5 usage report"
  echo -e "**Version:** $VERSION\n"
  echo -e "**Commit:** $COMMIT\n"

  catalog "Header \"Content-MD5\":" \
    "Used to provide message integrity checking for the message body, not for encryption."
  rg -t erlang -t elixir Content-MD5 -i -l
  echo

  catalog "Module: couch_hash:" \
    "FIPS mode can be enabled at compile time or runtime."
  if [ "$print_only" = true ]; then
    comby '%% FIPS (:[1])' '' -lang .txt -d src
  else
    comby '%% FIPS (:[1])' '' -lang .txt -d src | remove_color
  fi
  echo

  catalog "Other modules:" \
    "Only for test cases or to encrypt attachments."
  if [ "$print_only" = true ]; then
    comby '%% FIPS-ignore (:[1])' '' -d src -lang .txt
  else
    comby '%% FIPS-ignore (:[1])' '' -d src -lang .txt | remove_color
  fi
}

catalog() {
  echo "## $1"
  echo -e "$2\n"
}

remove_color() {
  sed 's/\x1B\[[0-9;]\{1,\}[A-Za-z]//g'
}

menu() {
  echo -ne "
FIPS md5 report generator script
1) Display in the console
2) Generate FIPS-report.md
Choose an option:  "
  read -r option
  case $option in
  1)
    print_only=true
    gen_report
    ;;
  2)
    gen_report >fips-report.md
    ;;
  *)
    echo "Wrong option!!!"
    exit 1
    ;;
  esac
}

menu
