#!/usr/bin/env bats
#
# Every test runs against a throwaway hosts file and state dir, with DNS
# flushing and launchctl switched off, so nothing on the real system is touched.

setup() {
  TMP="$(mktemp -d)"
  export LOCKIN_HOSTS="$TMP/hosts"
  export LOCKIN_STATE_DIR="$TMP/state"
  export LOCKIN_LAUNCHD_DIR="$TMP/launchd"
  export LOCKIN_NO_FLUSH=1
  export LOCKIN_NO_LAUNCHD=1
  export LOCKIN_NOW=1000000000
  printf '127.0.0.1\tlocalhost\n255.255.255.255\tbroadcasthost\n::1             localhost\n\n' > "$LOCKIN_HOSTS"
  cp "$LOCKIN_HOSTS" "$TMP/hosts.orig"
  FB="$BATS_TEST_DIRNAME/../bin/lockin"
}

teardown() {
  rm -rf "$TMP"
}

count() { grep -c "$1" "$LOCKIN_HOSTS" || true; }

# --- basics -----------------------------------------------------------------

@test "no arguments prints usage" {
  run "$FB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "unknown command fails" {
  run "$FB" explode
  [ "$status" -eq 1 ]
}

@test "--version prints the version" {
  run "$FB" --version
  [[ "$output" =~ ^lockin\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "lists shows the built-in lists" {
  run "$FB" lists
  [ "$status" -eq 0 ]
  [[ "$output" == *"netflix"* ]]
  [[ "$output" == *"youtube"* ]]
}

# --- blocking ---------------------------------------------------------------

@test "on netflix blocks Netflix over IPv4 and IPv6" {
  run "$FB" on netflix
  [ "$status" -eq 0 ]
  [ "$(count '^0\.0\.0\.0 www\.netflix\.com$')" -eq 1 ]
  [ "$(count '^:: www\.netflix\.com$')" -eq 1 ]
}

@test "off restores the original hosts file byte for byte" {
  "$FB" on netflix youtube
  run "$FB" off
  [ "$status" -eq 0 ]
  cmp "$LOCKIN_HOSTS" "$TMP/hosts.orig"
}

@test "round trip also works when the file has no trailing blank line" {
  printf '127.0.0.1 localhost' > "$LOCKIN_HOSTS"
  printf '127.0.0.1 localhost\n' > "$TMP/hosts.orig"
  "$FB" on netflix
  "$FB" off
  cmp "$LOCKIN_HOSTS" "$TMP/hosts.orig"
}

@test "running on twice does not duplicate entries" {
  "$FB" on netflix
  "$FB" on netflix
  [ "$(count '^0\.0\.0\.0 netflix\.com$')" -eq 1 ]
  [ "$(count 'LOCKIN-START')" -eq 1 ]
}

@test "a second on adds to the existing block" {
  "$FB" on netflix
  "$FB" on youtube
  [ "$(count '^0\.0\.0\.0 netflix\.com$')" -eq 1 ]
  [ "$(count '^0\.0\.0\.0 youtube\.com$')" -eq 1 ]
  run "$FB" status
  [[ "$output" == *"netflix, youtube"* ]]
}

@test "list names are case-insensitive" {
  run "$FB" on NetFlix
  [ "$status" -eq 0 ]
  [ "$(count '^0\.0\.0\.0 netflix\.com$')" -eq 1 ]
}

@test "a raw domain is blocked together with its www. variant" {
  "$FB" on example.com
  [ "$(count '^0\.0\.0\.0 example\.com$')" -eq 1 ]
  [ "$(count '^0\.0\.0\.0 www\.example\.com$')" -eq 1 ]
}

@test "unknown targets are rejected and the file is left alone" {
  run "$FB" on notalist
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown site or list"* ]]
  cmp "$LOCKIN_HOSTS" "$TMP/hosts.orig"
}

@test "anything that isn't a hostname is rejected" {
  for bad in 'evil.com;rm' 'a b.com' '-x.com' 'bad..com' '../etc' '*'; do
    run "$FB" on "$bad"
    [ "$status" -eq 1 ]
  done
  cmp "$LOCKIN_HOSTS" "$TMP/hosts.orig"
}

@test "on with no target fails" {
  run "$FB" on
  [ "$status" -eq 1 ]
}

@test "--dry-run shows the block but changes nothing" {
  run "$FB" --dry-run on netflix --for 1h
  [ "$status" -eq 0 ]
  [[ "$output" == *"0.0.0.0 netflix.com"* ]]
  [[ "$output" == *"locked until"* ]]
  cmp "$LOCKIN_HOSTS" "$TMP/hosts.orig"
  [ ! -e "$LOCKIN_STATE_DIR/until" ]
}

@test "the first change saves a backup of the original file" {
  "$FB" on netflix
  cmp "$LOCKIN_STATE_DIR/hosts.backup" "$TMP/hosts.orig"
}

@test "a read-only hosts file gives a sudo hint" {
  [ "$(id -u)" -ne 0 ] || skip "root can write read-only files"
  chmod 444 "$LOCKIN_HOSTS"
  run "$FB" on netflix
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo"* ]]
}

@test "off when nothing is blocked is harmless" {
  run "$FB" off
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing is blocked"* ]]
}

# --- timer ------------------------------------------------------------------

@test "--for parses combined durations" {
  "$FB" on netflix --for 1h30m
  [ "$(cat "$LOCKIN_STATE_DIR/until")" -eq $((1000000000 + 5400)) ]
}

@test "--for=VALUE form works" {
  "$FB" on netflix --for=2d
  [ "$(cat "$LOCKIN_STATE_DIR/until")" -eq $((1000000000 + 172800)) ]
}

@test "bad durations are rejected" {
  for bad in 2x 0m h1 '' 1.5h; do
    run "$FB" on netflix --for "$bad"
    [ "$status" -eq 1 ]
  done
  cmp "$LOCKIN_HOSTS" "$TMP/hosts.orig"
}

@test "off refuses while the timer is running" {
  "$FB" on netflix --for 2h
  run "$FB" off
  [ "$status" -eq 1 ]
  [[ "$output" == *"You can do it!"* ]]
  [ "$(count '^0\.0\.0\.0 netflix\.com$')" -eq 1 ]
}

@test "off works once the timer is up" {
  "$FB" on netflix --for 2h
  LOCKIN_NOW=$((1000000000 + 7200)) run "$FB" off
  [ "$status" -eq 0 ]
  cmp "$LOCKIN_HOSTS" "$TMP/hosts.orig"
}

@test "a timer can be extended but not shortened" {
  "$FB" on netflix --for 2h
  run "$FB" on netflix --for 10m
  [[ "$output" == *"Keeping the later time"* ]]
  [ "$(cat "$LOCKIN_STATE_DIR/until")" -eq $((1000000000 + 7200)) ]
  "$FB" on netflix --for 3h
  [ "$(cat "$LOCKIN_STATE_DIR/until")" -eq $((1000000000 + 10800)) ]
}

@test "status shows the time left" {
  "$FB" on netflix --for 1h30m
  run "$FB" status
  [[ "$output" == *"1h 30m left"* ]]
}

@test "--for installs a launchd job that runs tick every minute" {
  "$FB" on netflix --for 1h
  plist="$LOCKIN_LAUNCHD_DIR/local.lockin.timer.plist"
  [ -f "$plist" ]
  grep -q '<string>tick</string>' "$plist"
  grep -q '<integer>60</integer>' "$plist"
  [ -x "$LOCKIN_STATE_DIR/lockin" ]
}

@test "tick does nothing before the timer is up" {
  "$FB" on netflix --for 1h
  LOCKIN_NOW=$((1000000000 + 3599)) "$FB" tick
  [ "$(count '^0\.0\.0\.0 netflix\.com$')" -eq 1 ]
}

@test "tick lifts the block and cleans up once the timer is up" {
  "$FB" on netflix --for 1h
  LOCKIN_NOW=$((1000000000 + 3600)) "$FB" tick
  cmp "$LOCKIN_HOSTS" "$TMP/hosts.orig"
  [ ! -e "$LOCKIN_STATE_DIR/until" ]
  [ ! -e "$LOCKIN_LAUNCHD_DIR/local.lockin.timer.plist" ]
}

@test "the copied tick runner works on its own" {
  "$FB" on netflix --for 1h
  LOCKIN_NOW=$((1000000000 + 3600)) "$LOCKIN_STATE_DIR/lockin" tick
  cmp "$LOCKIN_HOSTS" "$TMP/hosts.orig"
}
