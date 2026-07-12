[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/M4M81TUBKF)

# Docker - Palworld Dedicated Server Wine

This is a modified version of a linux palworld server to use the Windows version the Palworld server instead of Linux. I've tried my best to make everything else from the previous repository work in this version, but there will probably be some incompatibilities.
___

[![Build-Status develop](https://github.com/ripps818/docker-palworld-dedicated-server-wine/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/ripps818/docker-palworld-dedicated-server-wine/actions/workflows/docker-publish.yml)

This Docker image includes a Palworld Dedicated Server based on Wine and Docker.


___

> [!WARNING]
> **Heads-up — RCON has been removed.** This image no longer uses RCON for any container tooling. All server management (player detection, backups, restarts, CLI) now runs via the Palworld REST API.
> - `RCON_ENABLED` now defaults to `false` — this only controls the game server INI setting, not container functionality.
> - Make sure `RESTAPI_ENABLED=true` is set in your `default.env`.
> - See the [Changelog](#changelog) for the full migration guide and renamed environment variables.

___

> [!CAUTION]
> **Public Service Announcement — Custom Script Feature**
>
> After many community requests, this image now supports running a custom script before the server starts.
> This feature is entirely **opt-in** and is controlled by the `CUSTOM_SCRIPT_ENABLED` environment variable, which defaults to `false`.
>
> **This image will never ship with a custom script of any kind.**
>
> If you come across a Docker image that appears to be this one but includes a bundled custom script, please be careful — it is not this image and I have no affiliation with it.
>
> This feature was added at the request of the community. While I am glad to offer the option, I will not be providing support for it, and I refuse to accept **any liability** for any harm, data loss, corruption, or security issues that may result from its use. Please use it at your own discretion. — Public Service Announcement.

## Table of Contents

- [Docker - Palworld Dedicated Server](#docker---palworld-dedicated-server)
  - [Table of Contents](#table-of-contents)
  - [How to ask for support for this Docker image](#how-to-ask-for-support-for-this-docker-image)
  - [Requirements](#requirements)
  - [Minimum system requirements](#minimum-system-requirements)
  - [Changelog](#changelog)
  - [Getting started](#getting-started)
  - [Installing Mods](#installing-mods)
  - [Environment variables](#environment-variables)
  - [Docker-Compose examples](#docker-compose-examples)
    - [Gameserver with REST API](#gameserver-with-rest-api)
  - [Run REST API commands](#run-rest-api-commands)
  - [Backup Manager](#backup-manager)
  - [Webhook integration](#webhook-integration)
    - [Supported events](#supported-events)
  - [Deploy with Helm](#deploy-with-helm)
  - [FAQ](#faq)
    - [Does this image support Xbox Dedicated Servers?](#does-this-image-support-xbox-dedicated-servers)
    - [How can I use the interactive console in Portainer with this image?](#how-can-i-use-the-interactive-console-in-portainer-with-this-image)
    - [How can I look into the config of my Palworld container?](#how-can-i-look-into-the-config-of-my-palworld-container)
    - [I'm seeing S\_API errors in my logs when I start the container?](#im-seeing-s_api-errors-in-my-logs-when-i-start-the-container)
    - [I'm using Apple silicon type of hardware, can I run this?](#im-using-apple-silicon-type-of-hardware-can-i-run-this)
    - [I changed the `BaseCampWorkerMaxNum` setting, why didn't this update the server?](#i-changed-the-basecampworkermaxnum-setting-why-didnt-this-update-the-server)
  - [Planned features in the future](#planned-features-in-the-future)
  - [Software used](#software-used)

## How to ask for support for this Docker image

If you need support for this Docker image:

- Feel free to create a new issue.
  - You can reference other issues if you're experiencing a similar problem via #issue-number.
- Follow the instructions and answer the questions of people who are willing to help you.
- Once your issue is resolved, please close it and please consider giving this repo a star.
- Please note that any issue that has been inactive for a week will be closed due to inactivity.

Please avoid:

- Reusing or necroing issues. This can lead to spam and may harass participants who didn't agree to be part of your new problem.
- If this happens, we reserve the right to lock the issue or delete the comments, you have been warned!

## Requirements

To run this Docker image, you need a basic understanding of Docker, Docker-Compose, Linux, and Networking (Port-Forwarding/NAT).

## Minimum system requirements

| Resource | 1-8 players                   | 8-12+ players                  |
| -------- | ----------------------------- | ------------------------------ |
| CPU      | 4 CPU-Cores @ High GHz        | 6-8 CPU Cores @ High GHz       |
| RAM      | 8GB RAM Base + 2GB per player | 12GB RAM Base + 2GB per player |
| Storage  | 30GB                          | 30GB+                          |

## Changelog

You can find the [changelog here](CHANGELOG.md)

## Getting started

1. Create a `game` sub-directory on your Docker-Node in your game-server-directory 
   - (Examples: `/srv/palworld`, `/opt/palworld` or `/home/username/palworld`)
   - This directory will be used to store the game server files, including configs and savegames
   - In older versions we asked you to setup permissions via CHMOD or CHOWN, this should not be needed anymore!
2. Set up Port-Forwarding or NAT for the ports in the Docker-Compose file
3. Pull the latest version of the image with `docker pull ghcr.io/ripps818/palworld-dedicated-server-wine:latest`
4. Download the [docker-compose.yml](docker-compose.yml) and [default.env](default.env)
5. Set up the `docker-compose.yml` and `default.env` to your liking
   - Make sure you setup PUID and PGID according to the user you want to use
     - **PUID and PGID 0 will error out, thats on purpose!**
     - if you use Docker as root, then you can just use 1000 inside the container
   - Refer to the [Environment-Variables](#environment-variables) section for more information
6. Start the container via `docker-compose up -d && docker-compose logs -f`
   - Watch the log, if no errors occur you can close the logs with ctrl+c
7. Now have fun and happy gaming! 🎮😉

## Installing Mods

This Palworld Windows server supports installing mods manually (via UE4SS) or automatically via the Steam Workshop.

### Automatic Mods via Steam Workshop

Palworld Dedicated Server supports automatic mod installation and updates directly from the Steam Workshop. Mods sourced this way (including UE4SS itself, if published on the Workshop with the appropriate InstallRules) are deployed automatically by the server's own mod-manifest system on startup or restart. You do **not** need to manually download or place files into the game directories.

#### Configuration
You can specify which Workshop mods to install using either environment variables or a configuration file:

1. **Via Environment Variable:**
   Set the `WORKSHOP_MOD_IDS` environment variable to a comma-separated list of Published File IDs:
   ```yaml
   environment:
     - WORKSHOP_MOD_IDS=3142718104,3142718105
   ```
2. **Via Config File:**
   Create a file named `workshop-mods.txt` in the root of your bind-mounted game directory (e.g., `./game/workshop-mods.txt`).
   Add one Published File ID per line. Lines starting with `#` are treated as comments and blank lines are ignored:
   ```text
   # My Favorite Mods
   3142718104
   3142718105
   ```

*Note: If both sources are populated, the lists are merged and deduplicated.*

#### How to Find a Mod's Published File ID
Go to the Palworld Steam Workshop page, find a mod you want to install, and look at its URL. The ID is the number at the end of the `?id=` parameter:
- **URL:** `https://steamcommunity.com/sharedfiles/filedetails/?id=3142718104`
- **ID:** `3142718104`

#### Automatic Update Checks
By default, the container checks for mod updates every 6 hours via the `WORKSHOP_MOD_UPDATE_CRON` environment variable (`0 */6 * * *`). 
- When an update is detected, the container uses the REST API to broadcast warnings to connected players, save the world, shut down safely, and restart.
- You can change the cron schedule by setting `WORKSHOP_MOD_UPDATE_CRON` to a different cron expression, or set it to empty (`""`) to disable periodic checks (mods will still be installed/updated once at container startup).

---

### Manual Mod Installation (UE4SS)

If you prefer to install mods manually or have mods not available on the Steam Workshop, you can install the UE4SS framework:

1. Download the latest version of [UE4SS 3.0.0 or newer](https://github.com/UE4SS-RE/RE-UE4SS/releases)
2. Unzip it into `./game/Pal/Binaries/Win64` (assuming `./game/` is the host directory bound to `/palworld` in the container)
3. Edit `UE4SS-settings.ini` to configure the following settings:
   ```ini
   bUseUObjectArrayCache = false
   GuiConsoleEnabled = 0
   ```
4. Install mods into the `Mods` folder and follow the installation instructions for each mod. Some mods may require editing `mods.txt` or installing parts of the mod into the generated LogicMods folder.

## Environment variables

See [this file](/docs/ENV_VARS.md) for the documentation

## Docker-Compose examples

### Gameserver with REST API

<!-- compose-start -->
```yaml
networks:
  palworld:

services:
  palworld-dedicated-server:
    container_name: palworld-wine-server
    image: ghcr.io/ripps818/docker-palworld-dedicated-server-wine:latest
    restart: unless-stopped
    logging:
      driver: "local"
      options:
        max-size: "10m"
        max-file: "3"
    ports:
      - target: 8211 # Gamerserver port inside of the container
        published: 8211 # Gamerserver port on your host
        protocol: udp
        mode: host
      - target: 8212 # Gameserver API port inside of the container
        published: 8212 # Gameserver API port on your host
        protocol: tcp
        mode: host
      - target: 25575 # RCON port inside of the container
        published: 25575 # RCON port on your host
        protocol: tcp
        mode: host
      - target: 27015 # Query port inside of the container
        published: 27015 # Query port on your host
        protocol: tcp
    env_file:
      - ./default.env
    volumes:
      - ./game:/palworld
    networks:
      - palworld

```
<!-- compose-end -->

## Run REST API commands

> [!NOTE]
> Please research the REST API commands on the official source: https://docs.palworldgame.com/category/rest-api

You can use `docker exec palworld-wine-server restapicli <command>` right on your terminal/shell.

```shell
$ docker exec palworld-wine-server restapicli players
> Players: {"players": [...]}

$ docker exec palworld-wine-server restapicli info
> Server info: {"version": "v0.7.3.90464", "servername": "...", ...}

$ docker exec palworld-wine-server restapicli metrics
> Metrics: {"currentplayernum": 1, "serverfps": 120, ...}

$ docker exec palworld-wine-server restapicli save
> Saving world...
> World saved.

$ docker exec palworld-wine-server restapicli announce "Hello players!"
> Announced: Hello players!

$ docker exec palworld-wine-server restapicli kick steam_76000000000000123 "Goodbye!"
> Kicked: steam_76000000000000123

$ docker exec palworld-wine-server restapicli ban steam_76000000000000123 "You are banned."
> Banned: steam_76000000000000123

$ docker exec palworld-wine-server restapicli unban steam_76000000000000123
> Unbanned: steam_76000000000000123

$ docker exec palworld-wine-server restapicli banlist
> Ban list (2 entries):
steam_76000000000000123
steam_76000000000000456

$ docker exec palworld-wine-server restapicli shutdown 60 "Server restarting soon"
> Shutting down server in 60s...
> Shutdown issued.
```

## Backup Manager

> [!WARNING]
> If `RESTAPI_ENABLED` is set to `false`, the backup manager will not announce backup start/success/failure in-game and will not trigger a world save before creating a backup.
> This means that the backup will be created from the last auto-save of the server.
> This can lead to data-loss and/or savegame corruption.
>
> **Recommendation:** Please make sure that `RESTAPI_ENABLED=true` is set before using the backup manager.

> [!WARNING]
> Please use in the following part always the `--user steam` option or your files will be written as root


Usage: `docker exec --user steam palworld-wine-server backup [command] [arguments]`

| Command | Argument           | Required/Optional | Default Value                     | Values           | Description                                                                                                                                                                          |
| ------- | ------------------ | ----------------- | --------------------------------- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| create  | N/A                | N/A               | N/A                               | N/A              | Creates a backup.                                                                                                                                                                    |
| list    | `<number_to_list>` | Optional          | N/A                               | Positive numbers | Lists all backups.<br>If `<number_to_list>` is specified, only the most<br>recent `<number_to_list>` backups are listed.                                                             |
| clean   | `<number_to_keep>` | Optional          | `BACKUP_RETENTION_AMOUNT_TO_KEEP` | Positive numbers | Cleans up backups.<br>If `<number_to_list>` is specified, cleans and keeps<br>the most recent`<number_to_keep>` backups.<br>If not, default to `BACKUP_RETENTION_AMOUNT_TO_KEEP` var |

Examples:

```shell
$ docker exec --user steam palworld-wine-server backup create
>>> Backup 'saved-20240203_032855.tar.gz' created successfully
```

```shell
$ docker exec --user steam palworld-wine-server backup list
>>> Listing 2 backup file(s)!
2024-02-03 03:28:55 | saved-20240203_032855.tar.gz
2024-02-03 03:28:00 | saved-20240203_032800.tar.gz
```

```shell
$ docker exec --user steam palworld-wine-server backup clean 3
>>> 1 backup(s) cleaned, keeping 2 backup(s).
```

```shell
$ docker exec --user steam palworld-wine-server backup list 1
>>> Listing 1 out of 2 backup file(s).
2024-02-03 03:30:00 | saved-20240203_033000.tar.gz
```

## Webhook integration

To enable webhook integrations, you need to set the following environment variables in the `default.env`:

```shell
WEBHOOK_ENABLED=true
WEBHOOK_URL="https://your.webhook.url"
```

After enabling the server should send messages in a Discord-Compatible way to your webhook url.

> You can find more details about these variables [here](/docs/ENV_VARS.md#webhook-settings).

### Supported events

- Server starting 
  - This even is not server started. Just add like 5 seconds on top and the server is online
- Server stopped
- Server updating
- Server updating and validating

## Deploy with Helm

A Helm chart to deploy this container can be found at [palworld-helm](https://github.com/caleb-devops/palworld-helm).

## FAQ

### Does this image support Xbox Dedicated Servers?

> Yes just change the value from `ALLOW_CONNECT_PLATFORM` from Steam to Xbox. See here for more documentation: https://tech.palworldgame.com/getting-started/for-xbox-dedicated-server

### How can I use the interactive console in Portainer with this image?

> You can run this `docker exec -ti palworld-wine-server bash' or you could navigate to the **"Stacks"** tab in Portainer, select your stack, and click on the container name. Then click on the **"Exec console"** button.

### How can I look into the config of my Palworld container?

> You can run this `docker exec -ti palworld-wine-server cat /palworld/Pal/Saved/Config/WindowsServer/PalWorldSettings.ini` and it will show you the config inside the container.

### I'm seeing S_API errors in my logs when I start the container?

> Errors like `[S_API FAIL] Tried to access Steam interface SteamUser021 before SteamAPI_Init succeeded.` are safe to ignore.

### I'm using Apple silicon type of hardware, can I run this?

> You can try to insert in your docker-compose file this parameter `platform: linux/amd64` at the palworld service. This isn't a special fix for Apple silicon, but to run on other than x86 hosts. The support for arm exists only by enforcing x86 emulation, if that isn't to host already. Rosetta is doing the translation/emulation.

### I changed the `BaseCampWorkerMaxNum` setting, why didn't this update the server?

> This is a confirmed bug. Changing `BaseCampWorkerMaxNum` in the `PalWorldSettings.ini` has no effect on the server. There are tools out there to help with this, like this one: <https://github.com/legoduded/palworld-worldoptions>

> [!WARNING]
> Adding `WorldOption.sav` will break `PalWorldSetting.ini`. So any new changes to the settings (either on the file or via ENV VARS), you will have to create a new `WorldOption.sav` and update it every time for those changes to have an effect.

## Planned features in the future

- Feel free to suggest something. Under `Issues` there is a Feature Request issue-type.

## Software used

- CM2Network SteamCMD - Debian-based (Officially recommended by Valve - https://developer.valvesoftware.com/wiki/SteamCMD#Docker)
- Supercronic - https://github.com/aptible/supercronic
- jq - https://jqlang.org/
- Palworld Dedicated Server (APP-ID: 2394010 - https://steamdb.info/app/2394010/config/)
