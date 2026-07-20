#!/usr/bin/env bash

set -Eeuo pipefail

log() {
  printf '[ce-server] %s\n' "$*"
}

die() {
  printf '[ce-server] ERROR: %s\n' "$*" >&2
  return 1
}

validate_port() {
  local name="$1"
  local value="$2"

  [[ "$value" =~ ^[0-9]+$ ]] || {
    die "${name} must be an integer"
    return 1
  }
  ((value >= 1 && value <= 65535)) || {
    die "${name} must be between 1 and 65535"
    return 1
  }
}

validate_positive_integer() {
  local name="$1"
  local value="$2"

  [[ "$value" =~ ^[0-9]+$ ]] || {
    die "${name} must be a positive integer"
    return 1
  }
  ((value >= 1)) || {
    die "${name} must be a positive integer"
    return 1
  }
}

validate_boolean() {
  local name="$1"
  local value="$2"

  [[ "$value" == "true" || "$value" == "false" ]] || {
    die "${name} must be true or false"
    return 1
  }
}

validate_single_line() {
  local name="$1"
  local value="$2"

  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || {
    die "${name} must not contain line breaks"
    return 1
  }
}

set_defaults() {
  : "${SERVER_DIR:=/home/steam/server-files}"
  : "${STEAMCMD_BIN:=/opt/steamcmd/steamcmd.sh}"
  : "${UPDATE_ON_START:=true}"
  : "${STEAM_WORKSHOP_DIR:=${SERVER_DIR}/steamapps/workshop/content/440900}"
  : "${MOD_WORKSHOP_ITEMS:=}"
  : "${SERVER_NAME:=Conan Exiles Enhanced Server}"
  : "${SERVER_PASSWORD:=}"
  : "${ADMIN_PASSWORD:=}"
  : "${GAME_PORT:=7777}"
  : "${PING_PORT:=7778}"
  : "${QUERY_PORT:=27015}"
  : "${MAX_PLAYERS:=20}"
  : "${RCON_ENABLED:=false}"
  : "${RCON_PORT:=25575}"
  : "${RCON_PASSWORD:=}"
}

validate_environment() {
  set_defaults

  validate_boolean UPDATE_ON_START "$UPDATE_ON_START"
  validate_boolean RCON_ENABLED "$RCON_ENABLED"
  validate_single_line MOD_WORKSHOP_ITEMS "$MOD_WORKSHOP_ITEMS"
  validate_port GAME_PORT "$GAME_PORT"
  validate_port PING_PORT "$PING_PORT"
  validate_port QUERY_PORT "$QUERY_PORT"
  validate_port RCON_PORT "$RCON_PORT"
  validate_positive_integer MAX_PLAYERS "$MAX_PLAYERS"
  validate_single_line SERVER_NAME "$SERVER_NAME"
  validate_single_line SERVER_PASSWORD "$SERVER_PASSWORD"
  validate_single_line ADMIN_PASSWORD "$ADMIN_PASSWORD"
  validate_single_line RCON_PASSWORD "$RCON_PASSWORD"

  ((GAME_PORT < 65535)) || {
    die "GAME_PORT must leave room for the GAME_PORT+1 pinger port"
    return 1
  }
  [[ "$PING_PORT" == "$((GAME_PORT + 1))" ]] || {
    die "PING_PORT must equal GAME_PORT+1"
    return 1
  }
  [[ "$QUERY_PORT" != "$GAME_PORT" ]] || {
    die "QUERY_PORT must differ from GAME_PORT"
    return 1
  }
  [[ "$QUERY_PORT" != "$((GAME_PORT + 1))" ]] || {
    die "QUERY_PORT must differ from the GAME_PORT+1 pinger port"
    return 1
  }

  if [[ "$RCON_ENABLED" == "true" && -z "$RCON_PASSWORD" ]]; then
    die "RCON_PASSWORD is required when RCON_ENABLED=true"
    return 1
  fi

  parse_workshop_mod_items
}

assert_non_root() {
  ((EUID != 0)) || die "The server must not run as root"
}

install_or_update_server() {
  local steamcmd_bin="${STEAMCMD_BIN:-/opt/steamcmd/steamcmd.sh}"
  local server_dir="${SERVER_DIR:-/home/steam/server-files}"

  mkdir -p "$server_dir"
  log "Installing or validating official Conan Exiles Enhanced Dedicated Server files"
  "$steamcmd_bin" \
    +@sSteamCmdForcePlatformType linux \
    +force_install_dir "$server_dir" \
    +login anonymous \
    +app_update 443030 validate \
    +quit
}

parse_workshop_mod_items() {
  WORKSHOP_MOD_IDS=()
  WORKSHOP_MOD_PAKS=()

  [[ -n "${MOD_WORKSHOP_ITEMS:-}" ]] || return 0

  local -a entries
  local entry mod_id pak_name pak_key
  local -A seen_ids=()
  local -A seen_paks=()
  IFS=',' read -r -a entries <<< "$MOD_WORKSHOP_ITEMS"

  for entry in "${entries[@]}"; do
    if [[ ! "$entry" =~ ^([0-9]+):([A-Za-z0-9][A-Za-z0-9_.-]*[.]pak)$ ]]; then
      die "Invalid MOD_WORKSHOP_ITEMS entry: ${entry}"
      return 1
    fi

    mod_id="${BASH_REMATCH[1]}"
    pak_name="${BASH_REMATCH[2]}"
    pak_key="${pak_name,,}"

    [[ "$mod_id" != "0" ]] || {
      die "Workshop mod ID must be positive: ${mod_id}"
      return 1
    }
    [[ -z "${seen_ids[$mod_id]:-}" ]] || {
      die "Duplicate Workshop mod ID: ${mod_id}"
      return 1
    }
    [[ -z "${seen_paks[$pak_key]:-}" ]] || {
      die "Duplicate Workshop PAK name: ${pak_name}"
      return 1
    }

    seen_ids[$mod_id]=1
    seen_paks[$pak_key]=1
    WORKSHOP_MOD_IDS+=("$mod_id")
    WORKSHOP_MOD_PAKS+=("$pak_name")
  done
}

sync_workshop_mods() {
  parse_workshop_mod_items

  if ((${#WORKSHOP_MOD_IDS[@]} == 0)); then
    log "No Workshop mods configured"
    return 0
  fi

  local steamcmd_bin="${STEAMCMD_BIN:-/opt/steamcmd/steamcmd.sh}"
  local server_dir="${SERVER_DIR:-/home/steam/server-files}"
  local workshop_dir="${STEAM_WORKSHOP_DIR:-${server_dir}/steamapps/workshop/content/440900}"
  local mods_dir="${server_dir}/ConanSandbox/Mods"
  local -a steamcmd_args=(
    +force_install_dir "$server_dir"
    +login anonymous
  )
  local index mod_id pak_name source_path staging_dir

  for mod_id in "${WORKSHOP_MOD_IDS[@]}"; do
    steamcmd_args+=(+workshop_download_item 440900 "$mod_id" validate)
  done
  steamcmd_args+=(+logoff +quit)

  log "Downloading or validating ${#WORKSHOP_MOD_IDS[@]} Conan Exiles Workshop mods"
  "$steamcmd_bin" "${steamcmd_args[@]}"

  for index in "${!WORKSHOP_MOD_IDS[@]}"; do
    mod_id="${WORKSHOP_MOD_IDS[$index]}"
    pak_name="${WORKSHOP_MOD_PAKS[$index]}"
    source_path="${workshop_dir}/${mod_id}/${pak_name}"
    [[ -s "$source_path" ]] || {
      die "Workshop mod ${mod_id} did not provide expected PAK: ${pak_name}"
      return 1
    }
  done

  mkdir -p "$mods_dir"
  staging_dir="$(mktemp -d "${mods_dir}/.sync.XXXXXX")"

  for index in "${!WORKSHOP_MOD_IDS[@]}"; do
    mod_id="${WORKSHOP_MOD_IDS[$index]}"
    pak_name="${WORKSHOP_MOD_PAKS[$index]}"
    source_path="${workshop_dir}/${mod_id}/${pak_name}"
    cp -- "$source_path" "${staging_dir}/${pak_name}" || {
      rm -rf -- "$staging_dir"
      die "Failed staging Workshop PAK: ${pak_name}"
      return 1
    }
    printf '*%s\n' "$pak_name" >> "${staging_dir}/modlist.txt"
  done

  for pak_name in "${WORKSHOP_MOD_PAKS[@]}"; do
    mv -f -- "${staging_dir}/${pak_name}" "${mods_dir}/${pak_name}" || {
      rm -rf -- "$staging_dir"
      die "Failed installing Workshop PAK: ${pak_name}"
      return 1
    }
  done
  mv -f -- "${staging_dir}/modlist.txt" "${mods_dir}/modlist.txt" || {
    rm -rf -- "$staging_dir"
    die "Failed installing Workshop modlist.txt"
    return 1
  }
  rmdir -- "$staging_dir"

  log "Installed ${#WORKSHOP_MOD_IDS[@]} Workshop mods in configured load order"
}

set_ini_value() {
  local file="$1"
  local section="$2"
  local key="$3"
  local value="$4"

  crudini --set "$file" "$section" "$key" "$value"
}

delete_ini_value() {
  local file="$1"
  local section="$2"
  local key="$3"

  crudini --del "$file" "$section" "$key" 2>/dev/null || true
}

configure_server() {
  local config_dir="${SERVER_DIR}/ConanSandbox/Saved/Config/LinuxServer"
  local engine_ini="${config_dir}/Engine.ini"
  local game_ini="${config_dir}/Game.ini"
  local server_settings_ini="${config_dir}/ServerSettings.ini"

  mkdir -p "$config_dir"
  touch "$engine_ini" "$game_ini" "$server_settings_ini"

  set_ini_value "$engine_ini" OnlineSubsystem ServerName "$SERVER_NAME"
  if [[ -n "$SERVER_PASSWORD" ]]; then
    set_ini_value "$engine_ini" OnlineSubsystem ServerPassword "$SERVER_PASSWORD"
  else
    delete_ini_value "$engine_ini" OnlineSubsystem ServerPassword
  fi

  if [[ -n "$ADMIN_PASSWORD" ]]; then
    set_ini_value "$server_settings_ini" ServerSettings AdminPassword "$ADMIN_PASSWORD"
  fi

  if [[ "$RCON_ENABLED" == "true" ]]; then
    set_ini_value "$game_ini" RconPlugin RconEnabled 1
    set_ini_value "$game_ini" RconPlugin RconPort "$RCON_PORT"
    set_ini_value "$game_ini" RconPlugin RconPassword "$RCON_PASSWORD"
  else
    set_ini_value "$game_ini" RconPlugin RconEnabled 0
    delete_ini_value "$game_ini" RconPlugin RconPassword
  fi

  chmod 0600 "$engine_ini" "$game_ini" "$server_settings_ini"
}

build_server_args() {
  SERVER_ARGS=(
    /Game/Maps/ConanSandbox/ConanSandbox
    -server
    -log
    "-port=${GAME_PORT}"
    "-queryport=${QUERY_PORT}"
    "-MaxPlayers=${MAX_PLAYERS}"
  )
}

main() {
  validate_environment
  assert_non_root

  local executable="${SERVER_DIR}/ConanSandboxServer.sh"
  if [[ "$UPDATE_ON_START" == "true" || ! -x "$executable" ]]; then
    install_or_update_server
  else
    log "Skipping update because UPDATE_ON_START=false"
  fi

  [[ -x "$executable" ]] || die "Server executable not found after installation: ${executable}"

  sync_workshop_mods
  configure_server
  build_server_args
  log "Starting server '${SERVER_NAME}' on UDP ${GAME_PORT} (query UDP ${QUERY_PORT})"
  exec "$executable" "${SERVER_ARGS[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
