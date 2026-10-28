# project-launcher

One script that runs Hossein's three bot projects on any OS. It shows an
interactive menu, asks **which project you want to run**, clones the project if
it isn't on the machine yet, installs what's missing, and starts it with the
right command.

## Run it

```bash
bash run.sh
```

No clone needed either — this works straight from GitHub on any machine with
bash:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hossein-bozorg-zadeh/project-launcher/main/run.sh)
```

You'll see the menu:

```
  1) GRMTB                       (python)
  2) tg-dl                       (tgdl)
  3) subsource-telegram-bot      (worker)
-------------------------------------------
  4) Quit

Which project do you want to run? [1-3, 4=quit]
```

## How checkouts work

The launcher only **runs** projects — it never clones. Each project must be
cloned into `PROJECTS_ROOT` (default: the folder `run.sh` lives in; override
with `PROJECTS_DIR=…`). Pick a project that isn't there and the launcher simply
prints the exact `git clone` command to run; an existing clone is started
directly. Run `git pull` inside a clone to update it.

```bash
# example — what the launcher prints when GRMTB is missing:
git clone https://github.com/hossein-bozorg-zadeh/GRMTB.git /path/to/project-launcher/GRMTB
```

## What it does per project

| Project | Action |
| --- | --- |
| **GRMTB** | `pip install -r requirements.txt`, warns if `BOT_TOKEN`/`OWNER_ID` are missing, then `python bot.py` |
| **tg-dl** | If `.env` is missing it offers the `setup.sh` wizard; otherwise starts the aria2 daemon (if not running) and `python bot.py` |
| **subsource-telegram-bot** | Asks *run locally* or *deploy to Cloudflare* (see below) |

### The Worker: run locally or deploy with a Cloudflare API token

Picking **subsource-telegram-bot** gives you two options:

1. **Run locally** — applies the D1 migrations to the local database
   (`wrangler d1 migrations apply --local`), creates `.dev.vars` on first run
   (asks for `BOT_TOKEN` and `SUBSOURCE_API_KEY`, generates a random
   `TELEGRAM_WEBHOOK_SECRET` itself), then starts `wrangler dev` on
   `http://localhost:8787`.
2. **Deploy to Cloudflare** — asks for a **Cloudflare API token** (create it at
   [dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens),
   template *Edit Cloudflare Workers*), verifies it against the Cloudflare API,
   and saves it next to the script in `.cloudflare.env` (mode `600`) so you are
   never asked again. Wrangler picks the token up from the environment, so the
   interactive browser login is never needed. It then runs `deploy.sh --yes`,
   which creates/reuses the D1 database, applies all migrations, uploads the
   secrets, deploys the Worker and registers the Telegram webhook.

`ACCOUNT_ID` is optional — wrangler usually infers it from the token. Delete
`.cloudflare.env` to be prompted again.

## Options

```bash
PROJECTS_DIR=~/code bash run.sh   # where the clones (and .cloudflare.env) live
DRY_RUN=1 bash run.sh             # print commands instead of executing them
```

Secrets handling: `.dev.vars` and `.cloudflare.env` are written with mode `600`
and are covered by the projects' own `.gitignore` rules — they never get
committed.

## OS support

The script is plain bash (3.2-compatible — the version macOS ships with):

- **macOS / Linux** — works as-is.
- **Windows** — run it from [Git Bash](https://git-scm.com/download/win) or
  WSL. `python`/`python3`, `npm` and `git` must be reachable from that shell.
