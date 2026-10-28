#!/usr/bin/env bash
#
# project-launcher — interactive menu to run Hossein's bot projects anywhere.
#
# Works on macOS, Linux, and Windows (Git Bash or WSL). Bash 3.2 compatible.
#
#   bash run.sh                       # interactive menu
#   PROJECTS_DIR=~/code bash run.sh   # clone/keep the projects somewhere else
#   DRY_RUN=1 bash run.sh             # print the commands instead of executing
#
# One-line remote usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/hossein-bozorg-zadeh/project-launcher/main/run.sh)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GITHUB_USER="hossein-bozorg-zadeh"
PROJECTS_ROOT="${PROJECTS_DIR:-$SCRIPT_DIR}"

# --------------------------------------------------------------------------
# Project registry.
# fields: repo_name | type | description
# --------------------------------------------------------------------------
PROJECTS=(
  "GRMTB|python|GitHub/GitLab release monitor Telegram bot"
  "tg-dl|tgdl|Download-manager Telegram bot (aria2 + yt-dlp + Telethon)"
  "subsource-telegram-bot|worker|SubSource subtitle bot on Cloudflare Workers"
)

c_green='\033[0;32m'; c_yellow='\033[1;33m'; c_cyan='\033[0;36m'; c_dim='\033[2m'; c_off='\033[0m'
# Log helpers write to stderr: project_dir() runs inside $(…) so anything on
# stdout would be captured as its return value instead of shown.
info()  { printf "${c_green}[i]${c_off} %s\n" "$*" >&2; }
warn()  { printf "${c_yellow}[!]${c_off} %s\n" "$*" >&2; }
step()  { printf "\n${c_cyan}==> ${c_off}%s\n" "$*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

python_bin() {
  if have python3; then echo "python3"; elif have python; then echo "python"; else echo ""; fi
}

dry() { [ "${DRY_RUN:-0}" = "1" ]; }

# --------------------------------------------------------------------------
# The launcher does the whole run by itself: the project is cloned
# automatically if missing (into PROJECTS_ROOT, default: next to run.sh) and
# updated with git pull before it starts — no confirmation prompts.
# --------------------------------------------------------------------------
ensure_checkout() {
  repo="$1"
  target="$PROJECTS_ROOT/$repo"

  if [ -d "$target" ]; then
    step "Updating the existing clone"
    if dry; then
      echo "(dry-run) git -C $target pull --ff-only" >&2
    else
      git -C "$target" pull --ff-only >/dev/null 2>&1 || warn "Could not update (offline or local changes?) — using the clone as it is."
    fi
    echo "$target"
    return 0
  fi

  warn "'$repo' is not cloned yet — cloning it for you."
  if dry; then
    echo "(dry-run) git clone https://github.com/$GITHUB_USER/$repo.git $target" >&2
    return 1
  fi

  mkdir -p "$PROJECTS_ROOT"
  if have gh; then
    gh repo clone "$GITHUB_USER/$repo" "$target" || return 1
  else
    git clone "https://github.com/$GITHUB_USER/$repo.git" "$target" || return 1
  fi
  info "Cloned into $target."
  echo "$target"
}

# --------------------------------------------------------------------------
# Worker helpers (subsource-telegram-bot)
# --------------------------------------------------------------------------

# Create .dev.vars for the Worker by prompting for the two secrets; the
# Telegram webhook secret is generated locally so nothing else is needed.
ensure_worker_devvars() {
  if [ -f .dev.vars ]; then
    info ".dev.vars found."
    return 0
  fi
  if dry; then
    echo "(dry-run) would prompt for BOT_TOKEN / SUBSOURCE_API_KEY and write .dev.vars"
    return 0
  fi

  step "Worker configuration — writing .dev.vars"
  if [ -n "${BOT_TOKEN:-}" ]; then
    bot_token="$BOT_TOKEN"
    info "Using BOT_TOKEN from the environment."
  else
    printf "Telegram BOT_TOKEN (from @BotFather): "
    read -rs bot_token; printf "\n"
  fi
  if [ -n "${SUBSOURCE_API_KEY:-}" ]; then
    api_key="$SUBSOURCE_API_KEY"
    info "Using SUBSOURCE_API_KEY from the environment."
  else
    printf "SUBSOURCE_API_KEY: "
    read -rs api_key; printf "\n"
  fi
  if [ -z "$bot_token" ] || [ -z "$api_key" ]; then
    warn "Both tokens are required — aborting configuration."
    return 1
  fi

  if have openssl; then
    webhook_secret="$(openssl rand -hex 32)"
    info "Generated a random TELEGRAM_WEBHOOK_SECRET."
  else
    printf "TELEGRAM_WEBHOOK_SECRET (min 16 chars): "
    read -rs webhook_secret; printf "\n"
  fi

  (
    umask 177
    cat > .dev.vars <<EOF
BOT_TOKEN=$bot_token
SUBSOURCE_API_KEY=$api_key
TELEGRAM_WEBHOOK_SECRET=$webhook_secret
EOF
  )
  info "Wrote .dev.vars (permissions 600)."
}

# Load / ask for the Cloudflare API token used by wrangler, so deploying never
# needs the interactive browser login. Saved next to this script (mode 600).
ensure_cloudflare_token() {
  if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    info "Using CLOUDFLARE_API_TOKEN from the environment."
    return 0
  fi

  cf_file="$SCRIPT_DIR/.cloudflare.env"
  if [ -f "$cf_file" ]; then
    # shellcheck disable=SC1090
    . "$cf_file"
    export CLOUDFLARE_API_TOKEN
    [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ] && export CLOUDFLARE_ACCOUNT_ID
    info "Using the saved Cloudflare API token from $cf_file."
    return 0
  fi

  if dry; then
    echo "(dry-run) would prompt for a Cloudflare API token, verify it, and save it to $cf_file"
    return 1
  fi

  step "Cloudflare API token"
  echo "Create one at https://dash.cloudflare.com/profile/api-tokens (template 'Edit Cloudflare Workers')."
  printf "Paste the API token: "
  read -rs cf_token; printf "\n"
  if [ -z "$cf_token" ]; then
    warn "No token entered."
    return 1
  fi

  if have curl; then
    step "Verifying the token"
    verify="$(curl -s -H "Authorization: Bearer $cf_token" \
      "https://api.cloudflare.com/client/v4/user/tokens/verify" || true)"
    case "$verify" in
      *'"success":true'*) info "Token is valid." ;;
      *)
        warn "Cloudflare rejected the token (or the check failed). Nothing was saved."
        return 1
        ;;
    esac
  fi

  printf "Cloudflare ACCOUNT_ID (optional, Enter to skip): "
  read -r cf_account || cf_account=""

  (
    umask 177
    {
      echo "CLOUDFLARE_API_TOKEN=$cf_token"
      [ -n "$cf_account" ] && echo "CLOUDFLARE_ACCOUNT_ID=$cf_account"
    } > "$cf_file"
  )
  export CLOUDFLARE_API_TOKEN
  [ -n "$cf_account" ] && export CLOUDFLARE_ACCOUNT_ID
  info "Saved to $cf_file (permissions 600). Delete the file to be asked again."
}

run_worker() {
  if ! have npm; then warn "Node.js/npm is not installed."; return 1; fi
  if [ ! -d node_modules ]; then
    step "Installing npm dependencies"
    if dry; then echo "(dry-run) npm install"; else npm install; fi
  fi

  echo ""
  echo "  1) Run locally   (wrangler dev on http://localhost:8787)"
  echo "  2) Deploy to Cloudflare (uses your Cloudflare API token — no browser login)"
  echo "  b) Back"
  printf "What do you want to do with the Worker? [1/2/b] "
  read -r wchoice || return 0

  case "$wchoice" in
    1)
      step "Applying local D1 migrations"
      if dry; then
        echo "(dry-run) npx wrangler d1 migrations apply subsource-bot --local"
      else
        npx wrangler d1 migrations apply subsource-bot --local || warn "Local migrations failed — /health will return 503 until they are applied."
      fi
      ensure_worker_devvars || return 1
      step "Starting the Worker locally (Ctrl+C to stop)"
      if dry; then echo "(dry-run) npm run dev"; else npm run dev; fi
      ;;
    2)
      ensure_worker_devvars || return 1
      ensure_cloudflare_token || { info "Deploy skipped."; return 0; }
      step "Deploying (deploy.sh creates the D1 database, applies migrations, uploads secrets and registers the webhook)"
      if dry; then
        echo "(dry-run) bash deploy.sh --yes --skip-install"
      else
        bash deploy.sh --yes --skip-install
      fi
      ;;
    *) info "Back to the menu." ;;
  esac
}

run_python() {
  _py="$(python_bin)"
  if [ -z "$_py" ]; then warn "Python is not installed."; return 1; fi
  if [ ! -f "requirements.txt" ]; then warn "requirements.txt not found."; return 1; fi
  step "Installing Python dependencies"
  if dry; then
    echo "(dry-run) $_py -m pip install -r requirements.txt"
  else
    "$_py" -m pip install -q -r requirements.txt || warn "pip install failed — continuing anyway"
  fi
  step "Starting the bot (Ctrl+C to stop)"
  if dry; then
    echo "(dry-run) BOT_TOKEN=… OWNER_ID=… $_py bot.py"
  else
    if [ -z "${BOT_TOKEN:-}" ] || [ -z "${OWNER_ID:-}" ]; then
      warn "BOT_TOKEN / OWNER_ID are not exported — the bot will refuse to start."
      echo "      export BOT_TOKEN='...' OWNER_ID='...' first, or set them in your host panel."
    fi
    "$_py" bot.py
  fi
}

run_tgdl() {
  if [ ! -f ".env" ]; then
    warn "No .env found — the one-shot wizard configures everything (deps, .env, aria2, systemd):"
    echo "      bash setup.sh"
    if dry; then
      echo "(dry-run) bash setup.sh"
      return 0
    fi
    printf "Run the wizard now? [Y/n] "
    read -r answer || return 0
    case "$answer" in n*|N*) return 0 ;; esac
    bash setup.sh
    return 0
  fi
  if have aria2c; then
    if ! { have pgrep && pgrep -x aria2c >/dev/null 2>&1; }; then
      step "Starting aria2 daemon in the background"
      if dry; then echo "(dry-run) aria2c --conf-path=aria2.conf"; else
        aria2c --conf-path=aria2.conf >/dev/null 2>&1 &
      fi
    fi
  else
    warn "aria2c is not installed — torrents/direct downloads will not work (see README)."
  fi
  _py="$(python_bin)"
  [ -z "$_py" ] && { warn "Python is not installed."; return 1; }
  step "Starting tg-dl bot (Ctrl+C to stop)"
  if dry; then echo "(dry-run) $_py bot.py"; else "$_py" bot.py; fi
}

show_menu() {
  echo ""
  printf "${c_cyan}Hossein's project launcher${c_off}\n"
  echo "-------------------------------------------"
  i=1
  for item in "${PROJECTS[@]}"; do
    name="${item%%|*}"; rest="${item#*|}"
    type="${rest%%|*}"; desc="${rest#*|}"
    printf "  %2d) %-28s ${c_dim}(%s)${c_off}\n" "$i" "$name" "$type"
    printf "      %s\n" "$desc"
    i=$((i + 1))
  done
  echo "-------------------------------------------"
  printf "  %2d) Quit\n" "$i"
  quit_index=$i
  echo ""
  printf "Which project do you want to run? [1-%d, %d=quit] " "$((quit_index - 1))" "$quit_index"
}

launch() {
  item="$1"
  name="${item%%|*}"; rest="${item#*|}"
  type="${rest%%|*}"; desc="${rest#*|}"

  step "$name — $desc"
  dir="$(ensure_checkout "$name")" || { info "Skipped."; return 0; }
  cd "$dir" || return 1
  info "Project directory: $dir"

  case "$type" in
    python) run_python ;;
    tgdl)   run_tgdl ;;
    worker) run_worker ;;
    *)      warn "Unknown project type: $type" ;;
  esac
}

main() {
  if ! have git; then warn "git is required (install it first)."; exit 1; fi
  if dry; then info "DRY_RUN=1 — commands will be printed, not executed."; fi
  info "Projects live in: $PROJECTS_ROOT (override with PROJECTS_DIR=…)"

  while true; do
    show_menu
    read -r pick || exit 0
    case "$pick" in
      ''|*[!0-9]*) warn "Please enter a number."; continue ;;
    esac
    if [ "$pick" -eq "$quit_index" ]; then
      info "Bye!"
      exit 0
    fi
    if [ "$pick" -ge 1 ] && [ "$pick" -le ${#PROJECTS[@]} ]; then
      launch "${PROJECTS[$((pick - 1))]}"
    else
      warn "Out of range."
    fi
  done
}

main "$@"
