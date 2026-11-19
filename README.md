# voice-keeper

Headless, host-friendly rewrite of `discord-voice-joiner`. It logs your accounts into the Discord
gateway, puts them in a voice channel and keeps them there: reconnecting, resuming sessions and
re-joining on its own. Optionally you control it from Discord with slash commands.

Python 3.10+. Runs on Linux, no GUI, no prompts, no Windows-only modules.

## What changed from the original

| Original | Now |
|---|---|
| `cli/main.py` imports `win32api` (Windows only) and blocks on `input()` | headless, config-driven, SIGTERM-aware |
| Heartbeat sends a random number | sends the last sequence number, checks every ACK, drops zombie connections |
| Any drop means a full re-login | resumes the session (op 6) first, re-identifies only if the server refuses |
| Fixed 5-10 s retry | exponential backoff with jitter, shared identify pacing across accounts |
| Bad token retries forever | close code 4004 stops that account only |
| Voice state sent once | re-asserted after every reconnect; re-joined if kicked or moved (rate limited) |
| Tokens in `tokens.txt`, logged by prefix | tokens from env vars, never logged (log filter scrubs them) |
| GUI path used `ssl=False` | TLS verification stays on |
| CLI Identify `properties` had colliding empty keys (`{'': 'desktop'}`) | proper `os` / `browser` / ... keys |

Kept: up to 20 accounts, per-account channel, mute / deafen / video / stream, Random Event,
`tokens.txt` import, leave-voice-on-exit.

## Quick start (any Linux host or panel)

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env            # fill in tokens
cp config.example.json config.json   # fill in ids
python -m voicekeeper --check   # validates config, connects to nothing
python -m voicekeeper
```

### Pterodactyl

1. Use a Python egg whose Docker image is Python 3.10 or newer (3.11/3.12 is best).
2. Upload the project so that `main.py`, `requirements.txt`, `voicekeeper/` and your `config.json` sit
   in the server's root folder (`/home/container`).
3. Startup tab: set the start file to `main.py` and the requirements file to `requirements.txt`
   (the usual Python egg variables, `PY_FILE` and `REQUIREMENTS_FILE`). If the egg has no such variable, add
   `aiohttp` and `discord.py` to its packages variable instead.
4. Panels usually give you no way to add custom environment variables, so put the tokens straight into
   `config.json` as `"token": "..."` (instead of `token_env`) and keep that file private.
5. Start the server and read the console. `state.json` is written next to `config.json`.

The panel's Stop button sends SIGTERM; the accounts leave voice and disconnect cleanly before exit.
If the console shows `config error: ...`, nothing was started, fix the named line and start again.

Other panels that only run a start command: use `python -m voicekeeper` (or `python main.py`) and set the
variables from `.env.example` in the panel.

No `config.json`? Use env-only mode: `VK_TOKENS=tok1,tok2`, `VK_GUILD_ID`, `VK_CHANNEL_ID`
(plus optional `VK_SELF_MUTE/DEAF/VIDEO/STREAM`).

Importing the old setup: put `"tokens_file": "tokens.txt"` and a `"default_target"` in `config.json`;
accounts are named `acct1`, `acct2`, ... in file order.

### Docker

```bash
mkdir -p data && cp config.example.json data/config.json && sudo chown 10001 data
docker compose up -d --build
```

### systemd

See `deploy/voicekeeper.service` (assumes `/opt/voice-keeper`, a venv in `.venv`, a `voicekeeper` user).

## Control bot (optional)

Create an application at the Discord developer portal, add a **bot**, invite it to a server, and set:

```
VK_BOT_TOKEN=<bot token>
VK_OWNER_IDS=<your user id>[,<other ids>]
VK_COMMAND_GUILD_IDS=<server id>      # optional, makes commands appear instantly
```

On hosts without custom environment variables (Pterodactyl), put the same three values in `config.json`:
`"control_bot": {"token": "...", "owner_ids": ["<your id>"], "command_guild_ids": ["<server id>"]}`.
Environment variables override the file when both are set.

It fails closed: without owner ids the control bot stays off and the accounts keep running.
Commands (owner only, replies are ephemeral). `account` is an account name from the config, or `all`:

- `/vk panel` opens a button panel only you can see: an account dropdown (or all accounts), **Join...**
  (a form for server and channel id, prefilled from the selected account), **Leave**, **Refresh**, and
  toggles for Mute, Deafen, Video, Stream. The status list updates after every press. It expires after
  30 minutes; run `/vk panel` again. The dropdown lists the first 24 accounts, `all` always works.
- `/vk status`
- `/vk join account guild_id channel_id`
- `/vk leave account`
- `/vk flags account [mute] [deaf] [video] [stream]`

Changes are saved to `state.json` and survive restarts. If you later edit that account in
`config.json`, the config wins and the saved change for it is dropped.

## Health check

Set `VK_HEALTH_PORT` (and `VK_HEALTH_HOST=0.0.0.0` on platforms that route to the container).
`GET /healthz` returns counts only: total, connected, in voice, auth failed.

## Settings (`config.json` → `settings`)

| Key | Default | Meaning |
|---|---|---|
| `max_accounts` | 20 | extra accounts are ignored with a warning (original `MAX_WORKERS`) |
| `identify_interval` | 5.0 | minimum seconds between fresh logins across all accounts |
| `reconnect_base` / `reconnect_cap` | 5 / 300 | backoff window in seconds |
| `stable_after` | 60 | a session this long resets the backoff |
| `rejoin_delay` | 30 | wait before re-joining after being removed from the channel |
| `max_rejoins_per_hour` | 20 | per account |
| `leave_on_shutdown` | true | leave voice before closing |
| `random_event` | false | pick mute/deafen/video/stream randomly once per account, then keep it |
| `state_path` | `state.json` next to config | runtime changes |
| `identity` | see `config.py` | Identify properties, override here if Discord rejects them |

## Status of this build

- Tested here against an in-memory fake gateway (52 tests, panel logic included against a stubbed
  discord.py, so the real discord.py calls in `controlbot.py` are still unproven): identify, resume, invalid session,
  missed heartbeat ACK, fatal close code, kick and rejoin, rejoin cap, voice/stream changes,
  shutdown leave, config parsing, state persistence. Run them with `python -m pytest`.
- **Not run against the real Discord gateway.** `transport.py` (aiohttp), `health.py` and
  `controlbot.py` (discord.py) could not be imported where this was written (packages not
  installed), only syntax-checked. First real run is the real test.
- Unverified against the live gateway: the Identify `properties` and build numbers (copied from the
  original project, see the docstring in `config.py`), the stream opcodes 18/19 and their payloads
  (copied from the original), and whether user-account sessions receive `VOICE_STATE_UPDATE` for
  themselves. If they do not, `/vk status` shows `unconfirmed` and rejoin-after-kick is inactive;
  everything else keeps working because voice state is re-sent on every reconnect.
