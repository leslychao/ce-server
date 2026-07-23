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

test_calculates_next_0300_msk_restart() {
  load_entrypoint

  [[ "$(seconds_until_msk_hour 3 0)" == '86400' ]] &&
    [[ "$(seconds_until_msk_hour 3 82800)" == '3600' ]] &&
    [[ "$(seconds_until_msk_hour 3 3600)" == '82800' ]]
}

test_rejects_invalid_restart_hour() {
  load_entrypoint
  ! validate_hour AUTO_RESTART_MSK_HOUR -1 2>/dev/null &&
    ! validate_hour AUTO_RESTART_MSK_HOUR 24 2>/dev/null &&
    ! validate_hour AUTO_RESTART_MSK_HOUR text 2>/dev/null
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

test_parses_workshop_mods_in_load_order() {
  load_entrypoint
  MOD_WORKSHOP_ITEMS='111:First.pak,222:Second_Mod.pak'

  parse_workshop_mod_items

  [[ "${WORKSHOP_MOD_IDS[*]}" == '111 222' ]] &&
    [[ "${WORKSHOP_MOD_PAKS[*]}" == 'First.pak Second_Mod.pak' ]]
}

test_rejects_unsafe_workshop_mod_entries() {
  load_entrypoint

  MOD_WORKSHOP_ITEMS='111:../escape.pak'
  ! parse_workshop_mod_items 2>/dev/null &&
    MOD_WORKSHOP_ITEMS='not-an-id:Mod.pak' &&
    ! parse_workshop_mod_items 2>/dev/null &&
    MOD_WORKSHOP_ITEMS='01:LeadingZero.pak' &&
    ! parse_workshop_mod_items 2>/dev/null &&
    MOD_WORKSHOP_ITEMS='111:First.pak,' &&
    ! parse_workshop_mod_items 2>/dev/null &&
    MOD_WORKSHOP_ITEMS='111:First.pak,111:Second.pak' &&
    ! parse_workshop_mod_items 2>/dev/null &&
    MOD_WORKSHOP_ITEMS='111:Same.pak,222:Same.pak' &&
    ! parse_workshop_mod_items 2>/dev/null
}

test_downloads_workshop_mods_and_writes_modlist() {
  load_entrypoint
  local temp_dir mock_log mock_steamcmd mods_dir
  temp_dir="$(mktemp -d)"
  mock_log="${temp_dir}/steamcmd.log"
  mock_steamcmd="${temp_dir}/steamcmd.sh"
  mods_dir="${temp_dir}/server/ConanSandbox/Mods"

  cat > "$mock_steamcmd" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" > "$MOCK_STEAMCMD_LOG"
while (($#)); do
  if [[ "$1" == '+workshop_download_item' ]]; then
    app_id="$2"
    mod_id="$3"
    [[ "$app_id" == '440900' ]]
    mkdir -p "${STEAM_WORKSHOP_DIR}/${mod_id}"
    printf 'pak-%s' "$mod_id" > "${STEAM_WORKSHOP_DIR}/${mod_id}/${mod_id}.pak"
    shift 4
  else
    shift
  fi
done
MOCK
  chmod +x "$mock_steamcmd"

  export MOCK_STEAMCMD_LOG="$mock_log"
  export STEAM_WORKSHOP_DIR="${temp_dir}/workshop"
  STEAMCMD_BIN="$mock_steamcmd"
  SERVER_DIR="${temp_dir}/server"
  MOD_WORKSHOP_ITEMS='111:111.pak,222:222.pak'

  sync_workshop_mods

  local expected_modlist
  expected_modlist=$'*111.pak\n*222.pak'
  [[ "$(cat "${mods_dir}/modlist.txt")" == "$expected_modlist" ]] &&
    [[ "$(cat "${mods_dir}/111.pak")" == 'pak-111' ]] &&
    [[ "$(cat "${mods_dir}/222.pak")" == 'pak-222' ]] &&
    grep -Fq 'workshop_download_item 440900 111 validate' "$mock_log" &&
    grep -Fq 'workshop_download_item 440900 222 validate' "$mock_log"
  local status=$?
  rm -rf -- "$temp_dir"
  return "$status"
}

test_missing_workshop_pak_aborts_without_replacing_modlist() {
  load_entrypoint
  local temp_dir mock_steamcmd mods_dir
  temp_dir="$(mktemp -d)"
  mock_steamcmd="${temp_dir}/steamcmd.sh"
  mods_dir="${temp_dir}/server/ConanSandbox/Mods"

  printf '#!/usr/bin/env bash\nexit 0\n' > "$mock_steamcmd"
  chmod +x "$mock_steamcmd"
  mkdir -p "$mods_dir"
  printf '*Existing.pak\n' > "${mods_dir}/modlist.txt"

  export STEAM_WORKSHOP_DIR="${temp_dir}/workshop"
  STEAMCMD_BIN="$mock_steamcmd"
  SERVER_DIR="${temp_dir}/server"
  MOD_WORKSHOP_ITEMS='111:Missing.pak'

  ! sync_workshop_mods 2>/dev/null &&
    [[ "$(cat "${mods_dir}/modlist.txt")" == '*Existing.pak' ]]
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
run_test 'next 03:00 MSK restart delay is calculated' test_calculates_next_0300_msk_restart
run_test 'invalid scheduled restart hours are rejected' test_rejects_invalid_restart_hour
run_test 'SteamCMD downloads official Linux app 443030' test_steamcmd_uses_official_app_and_linux_platform
run_test 'Workshop mods preserve configured load order' test_parses_workshop_mods_in_load_order
run_test 'unsafe Workshop mod entries are rejected' test_rejects_unsafe_workshop_mod_entries
run_test 'Workshop mods are downloaded and modlist.txt is generated' test_downloads_workshop_mods_and_writes_modlist
run_test 'missing Workshop PAK aborts without replacing modlist.txt' test_missing_workshop_pak_aborts_without_replacing_modlist

if ((failures > 0)); then
  exit 1
fi
