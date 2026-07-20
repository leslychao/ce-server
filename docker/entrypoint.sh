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

  configure_server
  build_server_args
  log "Starting server '${SERVER_NAME}' on UDP ${GAME_PORT} (query UDP ${QUERY_PORT})"
  exec "$executable" "${SERVER_ARGS[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
