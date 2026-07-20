#!/usr/bin/env bash

set -Eeuo pipefail

test "$(id -u)" = 1000

# The image path exists only inside the runtime container.
# shellcheck disable=SC1091
source /usr/local/bin/entrypoint.sh

validate_environment
configure_server

config_dir="${SERVER_DIR}/ConanSandbox/Saved/Config/LinuxServer"
engine_ini="${config_dir}/Engine.ini"
game_ini="${config_dir}/Game.ini"
server_settings_ini="${config_dir}/ServerSettings.ini"

test "$(crudini --get "$engine_ini" OnlineSubsystem ServerName)" = 'Test Server'
test "$(crudini --get "$engine_ini" OnlineSubsystem ServerPassword)" = 'test-server-secret'
test "$(crudini --get "$server_settings_ini" ServerSettings AdminPassword)" = 'test-admin-secret'
test "$(crudini --get "$game_ini" RconPlugin RconEnabled)" = 0
test "$(stat -c '%a' "$engine_ini")" = 600
test "$(stat -c '%a' "$game_ini")" = 600
test "$(stat -c '%a' "$server_settings_ini")" = 600
