#!/usr/bin/env bash
#
# project-launcher — interactive menu to run Hossein's projects anywhere.
#
# Works on macOS, Linux, and Windows (Git Bash or WSL). Bash 3.2 compatible.
#
#   bash run.sh                  # interactive menu
#   PROJECTS_DIR=~/code bash run.sh   # look for projects in a custom folder
#   DRY_RUN=1 bash run.sh        # print the command instead of executing it
#
# One-line remote usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/hossein-bozorg-zadeh/project-launcher/main/run.sh)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GITHUB_USER="hossein-bozorg-zadeh"
DEFAULT_PROJECTS_DIR="$SCRIPT_DIR"

# --------------------------------------------------------------------------
# Project registry.
# fields: repo_name | type | description | extra local directory names to try
# --------------------------------------------------------------------------
PROJECTS=(
  "GRMTB|python|GitHub/GitLab release monitor Telegram bot|"
  "tg-dl|tgdl|Download-manager Telegram bot (aria2 + yt-dlp + Telethon)|"
  "subsource-telegram-bot|worker|SubSource subtitle bot on Cloudflare Workers|subsource-telegram-bot,Default Project"
  "hossein-bozorg-zadeh.github.io|site|Portfolio website (static)|"
  "wwuploader|legacy|Legacy 2022 Telegram uploader bot (python-telegram-bot v12)|"
  "hossein-bozorg-zadeh|docs|GitHub profile README (nothing to run)|"
  "sub|docs|Placeholder repo (only a LICENSE)|"
)

FORKS=(
  "mihon|Free and open source manga reader for Android"
  "extensions|Mihon/Tachiyomi source extensions"
  "extensions-source|Source code of the extensions"
  "mihonwebsite|Official website for the Mihon app"
  "mihon-preview|Mihon preview builds"
  "BPB-Worker-Panel|Cloudflare Worker subscription panel"
  "Ssh-User-management|PHP VPN user management panel"
  "aria2|The aria2 downloader itself (C++)"
)

c_green='\033[0;32m'; c_yellow='\033[1;33m'; c_cyan='\033[0;36m'; c_dim='\033[2m'; c_off='\033[0m'
info()  { printf "${c_green}[i]${c_off} %s\n" "$*"; }
warn()  { printf "${c_yellow}[!]${c_off} %s\n" "$*"; }
step()  { printf "\n${c_cyan}==> ${c_off}%s\n" "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

python_bin() {
  if have python3; then echo "python3"; elif have python; then echo "python"; else echo ""; fi
}

# Find a local checkout: PROJECTS_DIR (if set), the common roots, else offer a clone.
# extra is a comma-separated list of alternative directory names (may contain spaces).
find_project_dir() {
  repo="$1"; extra="$2"
  roots=()
  [ -n "${PROJECTS_DIR:-}" ] && roots+=("$PROJECTS_DIR")
  roots+=("$DEFAULT_PROJECTS_DIR" "$(pwd)")
  for base in "$HOME/Documents" "$HOME/projects" "$HOME/Projects" "$HOME/code"; do
    [ -d "$base" ] && roots+=("$base")
  done

  dirs=("$repo")
  if [ -n "$extra" ]; then
    _oldIFS="$IFS"; IFS=','
    for d in $extra; do dirs+=("$d"); done   # shellcheck disable=SC2086
    IFS="$_oldIFS"
  fi

  for dir in "${dirs[@]}"; do
    [ -n "$dir" ] || continue
    for root in "${roots[@]}"; do
      if [ -d "$root/$dir" ]; then
        echo "$root/$dir"
        return 0
      fi
    done
  done
  return 1
}

ensure_checkout() {
  _repo="$1"; _extra="$2"
  if _dir="$(find_project_dir "$_repo" "$_extra")"; then
    echo "$_dir"
    return 0
  fi

  warn "'$_repo' is not on this machine yet."
  _target="${PROJECTS_DIR:-$DEFAULT_PROJECTS_DIR}/$_repo"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "(dry-run) clone https://github.com/$GITHUB_USER/$_repo into $_target"
    return 1
  fi
  printf "Clone https://github.com/%s/%s into %s ? [Y/n] " "$GITHUB_USER" "$_repo" "$_target"
  read -r _answer || exit 0
  case "$_answer" in
    n*|N*) return 1 ;;
    *)
      mkdir -p "$(dirname "$_target")"
      if have gh; then
        gh repo clone "$GITHUB_USER/$_repo" "$_target" || return 1
      else
        git clone "https://github.com/$GITHUB_USER/$_repo.git" "$_target" || return 1
      fi
      echo "$_target"
      ;;
  esac
}

run_python() {
  _py="$(python_bin)"
  if [ -z "$_py" ]; then warn "Python is not installed."; return 1; fi
  if [ ! -f "requirements.txt" ]; then warn "requirements.txt not found."; return 1; fi
  step "Installing Python dependencies"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "(dry-run) $_py -m pip install -r requirements.txt"
  else
    "$_py" -m pip install -q -r requirements.txt || warn "pip install failed — continuing anyway"
  fi
  step "Starting the bot (Ctrl+C to stop)"
  if [ "${DRY_RUN:-0}" = "1" ]; then
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
    if [ "${DRY_RUN:-0}" != "1" ]; then
      printf "Run the wizard now? [Y/n] "
      read -r _answer || return 0
      case "$_answer" in n*|N*) return 0 ;; esac
      bash setup.sh
    fi
    return 0
  fi
  if have aria2c; then
    if ! { have pgrep && pgrep -x aria2c >/dev/null 2>&1; }; then
      step "Starting aria2 daemon in the background"
      if [ "${DRY_RUN:-0}" = "1" ]; then echo "(dry-run) aria2c --conf-path=aria2.conf"; else
        aria2c --conf-path=aria2.conf >/dev/null 2>&1 &
      fi
    fi
  else
    warn "aria2c is not installed — torrents/direct downloads will not work (see README)."
  fi
  _py="$(python_bin)"
  [ -z "$_py" ] && { warn "Python is not installed."; return 1; }
  step "Starting tg-dl bot (Ctrl+C to stop)"
  if [ "${DRY_RUN:-0}" = "1" ]; then echo "(dry-run) $_py bot.py"; else "$_py" bot.py; fi
}

run_worker() {
  if ! have npm; then warn "Node.js/npm is not installed."; return 1; fi
  if [ ! -d node_modules ]; then
    step "Installing npm dependencies"
    if [ "${DRY_RUN:-0}" = "1" ]; then echo "(dry-run) npm install"; else npm install; fi
  fi
  if [ ! -f .dev.vars ]; then
    warn "No .dev.vars — 'wrangler dev' will fail config validation until it exists (cp .dev.vars.example .dev.vars)."
  fi
  step "Starting the Worker locally on http://localhost:8787 (Ctrl+C to stop)"
  if [ "${DRY_RUN:-0}" = "1" ]; then echo "(dry-run) npm run dev"; else npm run dev; fi
}

run_site() {
  _py="$(python_bin)"
  if [ -n "$_py" ]; then
    step "Serving at http://localhost:8080 (Ctrl+C to stop)"
    if [ "${DRY_RUN:-0}" = "1" ]; then echo "(dry-run) $_py -m http.server 8080"; else "$_py" -m http.server 8080; fi
  elif have npx; then
    step "Serving at http://localhost:8080 (Ctrl+C to stop)"
    if [ "${DRY_RUN:-0}" = "1" ]; then echo "(dry-run) npx serve -l 8080"; else npx serve -l 8080; fi
  else
    warn "Neither Python nor npx found — open index.html directly in a browser (fetch() needs a server, so some parts won't load)."
  fi
}

run_legacy() {
  _py="$(python_bin)"
  [ -z "$_py" ] && { warn "Python is not installed."; return 1; }
  warn "wwuploader targets python-telegram-bot v12 (2022) and will not run on v20+. Only use it inside a pinned v12 virtualenv."
  step "Starting uploader.py (Ctrl+C to stop)"
  if [ "${DRY_RUN:-0}" = "1" ]; then echo "(dry-run) $_py uploader.py"; else "$_py" uploader.py; fi
}

show_menu() {
  echo ""
  printf "${c_cyan}Hossein's project launcher${c_off}\n"
  echo "-------------------------------------------"
  i=1
  for item in "${PROJECTS[@]}"; do
    name="${item%%|*}"; rest="${item#*|}"
    type="${rest%%|*}"; rest="${rest#*|}"
    desc="${rest%%|*}"
    printf "  %2d) %-28s ${c_dim}(%s)${c_off}\n" "$i" "$name" "$type"
    printf "      %s\n" "$desc"
    i=$((i + 1))
  done
  echo "-------------------------------------------"
  printf "  %2d) Forked repos (clone/open only)\n" "$i"
  forks_index=$i
  i=$((i + 1))
  printf "  %2d) Quit\n" "$i"
  quit_index=$i
  echo ""
  printf "Which project do you want to run? [1-%d, %d=forks, %d=quit] " "$((forks_index - 1))" "$forks_index" "$quit_index"
}

show_forks() {
  echo ""
  printf "${c_cyan}Forked repos${c_off} ${c_dim}(other people's projects you keep around)${c_off}\n"
  i=1
  for item in "${FORKS[@]}"; do
    name="${item%%|*}"; desc="${item#*|}"
    printf "  %2d) %-22s %s\n" "$i" "$name" "$desc"
    i=$((i + 1))
  done
  echo ""
  printf "Clone which? [1-%d, Enter= back] " "$((i - 1))"
  read -r pick || return 0
  [ -z "$pick" ] && return 0
  case "$pick" in
    ''|*[!0-9]*) warn "Not a number."; return 0 ;;
  esac
  if [ "$pick" -lt 1 ] || [ "$pick" -gt $((${#FORKS[@]})) ]; then warn "Out of range."; return 0; fi
  item="${FORKS[$((pick - 1))]}"
  repo="${item%%|*}"
  dir="$(ensure_checkout "$repo" "")" || return 0
  info "$repo is at: $dir"
  info "Check that repo's own README for how to build it — it is a fork of someone else's project."
}

launch() {
  item="$1"
  name="${item%%|*}"; rest="${item#*|}"
  type="${rest%%|*}"; rest="${rest#*|}"
  desc="${rest%%|*}"; extra="${rest#*|}"
  [ "$extra" = "$desc" ] && extra=""

  step "$name — $desc"
  dir="$(ensure_checkout "$name" "$extra")" || { info "Skipped."; return 0; }
  cd "$dir" || return 1
  info "Project directory: $dir"

  case "$type" in
    python) run_python ;;
    tgdl)   run_tgdl ;;
    worker) run_worker ;;
    site)   run_site ;;
    legacy) run_legacy ;;
    docs)   info "Nothing to run — this repo is documentation. Open README.md to edit it." ;;
    *)      warn "Unknown project type: $type" ;;
  esac
}

main() {
  if ! have git; then warn "git is required (install it first)."; exit 1; fi
  [ "${DRY_RUN:-0}" = "1" ] && info "DRY_RUN=1 — commands will be printed, not executed."

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
    if [ "$pick" -eq "$forks_index" ]; then
      show_forks
      continue
    fi
    if [ "$pick" -ge 1 ] && [ "$pick" -le ${#PROJECTS[@]} ]; then
      launch "${PROJECTS[$((pick - 1))]}"
    else
      warn "Out of range."
    fi
  done
}

main "$@"
