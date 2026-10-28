# project-launcher

One script that runs every project of
[@hossein-bozorg-zadeh](https://github.com/hossein-bozorg-zadeh) — on any OS.
It shows an interactive menu, asks **which project you want to run**, finds the
project on your machine (or clones it for you), installs what's missing, and
starts it with the right command.

## Run it

```bash
bash run.sh
```

No clone needed either — this works straight from GitHub on any machine with
bash:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hossein-bozorg-zadeh/project-launcher/main/run.sh)
```

You'll see a numbered menu:

```
  1) GRMTB                       (python)
  2) tg-dl                       (tgdl)
  3) subsource-telegram-bot      (worker)
  4) hossein-bozorg-zadeh.github.io (site)
  5) wwuploader                  (legacy)
  6) hossein-bozorg-zadeh        (docs)
  7) sub                         (docs)
-------------------------------------------
  8) Forked repos (clone/open only)
  9) Quit

Which project do you want to run? [1-7, 8=forks, 9=quit]
```

## What it does per project

| Project | Action |
| --- | --- |
| **GRMTB** | `pip install -r requirements.txt`, warns if `BOT_TOKEN`/`OWNER_ID` are missing, then `python bot.py` |
| **tg-dl** | If `.env` is missing it offers the `setup.sh` wizard; otherwise starts the aria2 daemon (if not running) and `python bot.py` |
| **subsource-telegram-bot** | `npm install` when needed, then `npm run dev` (Wrangler on `localhost:8787`) — warns if `.dev.vars` is missing |
| **hossein-bozorg-zadeh.github.io** | Serves the portfolio at `http://localhost:8080` (Python http.server, or `npx serve` as fallback) |
| **wwuploader** | Runs `uploader.py` after warning that it needs the 2022-era python-telegram-bot v12 |
| **profile / sub** | Documentation-only repos — nothing to execute |
| **Forks** (mihon, extensions, BPB-Worker-Panel, aria2, …) | Offers to clone; check the fork's own README for build steps |

## Where it looks for projects

The launcher searches, in order: `PROJECTS_DIR` (if set), the folder the script
lives in, your current directory, and `~/Documents`, `~/projects`,
`~/Projects`, `~/code`. For example `subsource-telegram-bot` is found either as
a folder of that name or as `Default Project` inside those roots.

If the chosen project isn't on the machine, it asks for confirmation and clones
it (using `gh` when available, plain `git` otherwise) into
`PROJECTS_DIR` (default: next to the script).

## Options

```bash
PROJECTS_DIR=~/code bash run.sh   # custom folder for checkouts
DRY_RUN=1 bash run.sh             # print commands instead of executing them
```

## OS support

The script is plain bash (3.2-compatible — the version macOS ships with):

- **macOS / Linux** — works as-is.
- **Windows** — run it from [Git Bash](https://git-scm.com/download/win) or
  WSL. `python`/`python3` and `npm` must be reachable from that shell.
