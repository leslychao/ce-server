#!/usr/bin/env bash

# Variables assigned in tests are consumed by the sourced entrypoint.
# shellcheck disable=SC2034

set -u

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
entrypoint="${project_root}/docker/entrypoint.sh"
failures=0

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}

run_test() {
  local name="$1"
  shift

  if ("$@"); then
    pass "$name"
  else
    fail "$name"
  fi
}

load_entrypoint() {
  # The source path is resolved dynamically from the repository root.
  # shellcheck disable=SC1090
  source "$entrypoint"
}

test_accepts_valid_ports() {
  load_entrypoint
  validate_port GAME_PORT 7777
  validate_port QUERY_PORT 27015
}

test_rejects_invalid_ports() {
  load_entrypoint
  ! validate_port GAME_PORT 0 2>/dev/null &&
    ! validate_port GAME_PORT 65536 2>/dev/null &&
    ! validate_port GAME_PORT text 2>/dev/null
}

test_rejects_multiline_configuration() {
  load_entrypoint
  ! validate_single_line SERVER_NAME $'first\nsecond' 2>/dev/null
}

test_requires_rcon_password_when_enabled() {
  load_entrypoint
  RCON_ENABLED=true
  RCON_PASSWORD=''
  ! validate_environment 2>/dev/null
}

test_requires_pinger_port_after_game_port() {
  load_entrypoint
  GAME_PORT=7777
  PING_PORT=9000
  ! validate_environment 2>/dev/null
}

test_server_arguments_do_not_contain_secrets() {
  load_entrypoint
  GAME_PORT=7777
  QUERY_PORT=27015
  MAX_PLAYERS=20
  SERVER_PASSWORD='server-secret'
  ADMIN_PASSWORD='admin-secret'
  RCON_PASSWORD='rcon-secret'

  build_server_args
  local rendered="${SERVER_ARGS[*]}"

  [[ "$rendered" != *server-secret* ]] &&
    [[ "$rendered" != *admin-secret* ]] &&
    [[ "$rendered" != *rcon-secret* ]]
}

test_steamcmd_uses_official_app_and_linux_platform() {
  load_entrypoint
  local temp_dir mock_log mock_steamcmd
  temp_dir="$(mktemp -d)"
  mock_log="${temp_dir}/steamcmd.log"
  mock_steamcmd="${temp_dir}/steamcmd.sh"

  # The variables must remain literal because they belong to the mock script.
  # shellcheck disable=SC2016
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" > "$MOCK_STEAMCMD_LOG"\n' > "$mock_steamcmd"
  chmod +x "$mock_steamcmd"

  MOCK_STEAMCMD_LOG="$mock_log" \
    STEAMCMD_BIN="$mock_steamcmd" \
    SERVER_DIR="${temp_dir}/server" \
    install_or_update_server

  grep -Fq '@sSteamCmdForcePlatformType linux' "$mock_log" &&
    grep -Fq 'app_update 443030 validate' "$mock_log"
  local status=$?
  rm -rf -- "$temp_dir"
  return "$status"
}

run_test 'valid ports are accepted' test_accepts_valid_ports
run_test 'invalid ports are rejected' test_rejects_invalid_ports
run_test 'multiline configuration is rejected' test_rejects_multiline_configuration
run_test 'RCON requires a password' test_requires_rcon_password_when_enabled
run_test 'pinger port must equal game port plus one' test_requires_pinger_port_after_game_port
run_test 'secrets are not exposed in process arguments' test_server_arguments_do_not_contain_secrets
run_test 'SteamCMD downloads official Linux app 443030' test_steamcmd_uses_official_app_and_linux_platform

if ((failures > 0)); then
  exit 1
fi
