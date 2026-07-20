# Conan Exiles Enhanced Dedicated Server

Собственный Docker-образ для нативного Linux dedicated server. Игровые файлы не
включены в образ: при первом запуске они скачиваются из Steam как официальный
Conan Exiles Dedicated Server, App ID `443030`.

## Требования

- Linux `amd64` или Docker Desktop с Linux containers;
- Docker Engine и Docker Compose v2;
- минимум 8 ГБ RAM и 25 ГБ свободного места;
- рекомендуется 4+ CPU, 16 ГБ RAM и 50+ ГБ на SSD.

## Быстрый запуск

1. Создайте локальный файл настроек с криптографически случайными паролями.

   PowerShell или PowerShell 7:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/generate-env.ps1
   ```

   Генератор не перезаписывает существующий `.env`. Ключ `-Force` предназначен
   только для осознанной ротации сразу всех паролей.

   Если PowerShell недоступен, создайте настройки вручную из шаблона:

   ```bash
   cp .env.example .env
   ```

2. Отредактируйте `.env`. Как минимум задайте `SERVER_NAME`. Для закрытого
   сервера также задайте `SERVER_PASSWORD`, а для администрирования — длинный
   случайный `ADMIN_PASSWORD`.

3. Соберите и запустите сервер.

   ```bash
   docker compose up -d --build
   docker compose logs -f server
   ```

Первый запуск занимает заметное время: SteamCMD обновит себя и скачает сервер.
Файлы игры, настройки и мир сохраняются в `./data`.

## Порты

| Порт | Протокол | Назначение |
|---|---|---|
| `7777` | UDP | игровой трафик |
| `7778` | UDP | pinger, всегда `GAME_PORT + 1` |
| `27015` | UDP | запросы списка серверов |
| `25575` | TCP | RCON, по умолчанию выключен |

Для доступа из интернета откройте три UDP-порта в firewall и пробросьте их на
Docker-host. При CGNAT потребуется белый IP или внешний UDP-туннель.

Если меняете `GAME_PORT`, одновременно установите `PING_PORT=GAME_PORT+1`.

## Моды

Клиент и сервер должны использовать одинаковые `.pak`-файлы в одинаковом
порядке. На Windows локальные моды клиента можно безопасно скопировать в
серверное хранилище и сгенерировать `data/ConanSandbox/Mods/modlist.txt`:

```powershell
docker compose stop server
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sync-client-mods.ps1
docker compose start server
```

По умолчанию скрипт останавливается, если клиентский `modlist.txt` содержит
отсутствующий `.pak`. Ключ `-SkipMissing` явно пропускает такие устаревшие
строки. Скрипт не удаляет лишние `.pak`: сервер загружает только файлы,
перечисленные в сгенерированном `modlist.txt`.

## RCON

RCON выключен и его порт не публикуется по умолчанию. Для включения задайте в
`.env`:

```dotenv
RCON_ENABLED=true
RCON_PASSWORD=длинный-случайный-пароль
```

Запускайте с дополнительным Compose-файлом:

```bash
docker compose -f compose.yaml -f compose.rcon.yaml up -d
```

Не публикуйте RCON в интернет без firewall allowlist или VPN.

## Управление

```bash
# Состояние
docker compose ps

# Логи
docker compose logs -f server

# Остановить, сохранив данные
docker compose down

# Запустить и проверить обновления Steam
docker compose up -d
```

При `UPDATE_ON_START=true` SteamCMD выполняет `app_update 443030 validate` перед
каждым запуском. Клиент и сервер должны иметь совместимые версии.

## Резервная копия

Для гарантированно согласованной копии сначала остановите сервер:

```bash
docker compose stop server
tar -czf conan-saved-backup.tar.gz data/ConanSandbox/Saved
docker compose start server
```

Основная база мира находится внутри `data/ConanSandbox/Saved`. Для Enhanced на
Linux имя `game.db` должно оставаться в нижнем регистре.

## Безопасность

- сервер работает от непривилегированного пользователя `steam`;
- Linux capabilities сброшены, включён `no-new-privileges`;
- пароли хранятся только в локальном `.env` и конфигурации игры;
- `.env` и `data/` исключены из Git;
- секреты не передаются в аргументах процесса сервера;
- базовый Debian-образ зафиксирован по digest.

Не публикуйте собранный образ вместе с содержимым `data/`: там находятся
серверные файлы Steam, сохранения и секреты.
