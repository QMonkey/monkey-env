#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# monkey-env one-shot meta-installer
#
# Chains the monkey-* component installers in dependency order:
#   monkey-zsh -> monkey-wezterm -> monkey-hyprland -> monkey-sway ->
#   monkey-tmux -> monkey-nvim -> monkey-vim
#   (runtime order: monkey-zsh and monkey-wezterm are hoisted to the
#   front — zsh's chsh must precede the later stages so their env blocks
#   land in ~/.zprofile; wezterm precedes the compositors because both
#   checkhealth scripts treat it as their default terminal and would
#   otherwise install it themselves, bypassing this component's source build.
#   monkey-sway is opt-in: --with-monkey-sway.
#   Default installs everything else, including monkey-hyprland — except
#   on WSL/macOS, where the default drops monkey-hyprland as well;
#   --with-monkey-hyprland overrides.)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-env/master/install.sh | bash
#   bash install.sh [OPTIONS]
#
# NOTE: `bash --with-monkey-tmux` does NOT work — bash would parse it as
# its own option. `bash -s --` ends bash's option parsing and forwards
# everything after `--` to this script as positional parameters.
#
# The shared components (colors, logging, sudo grant, TIOCSTI injection)
# live in scripts/ — a `git subtree` of github.com/QMonkey/monkey-scripts.
# On the curl|bash path there is no checkout at all, so install.sh clones
# THIS repo and runs the copy of install.sh inside it — that copy carries
# its own scripts/, so both come from the same revision. The component
# chain itself is this file's own main().
# ──────────────────────────────────────────────────────────────

# ──────────────────────── repository identity ────────────────────────
# Declared before the framework is sourced: the bootstrap below needs
# both values, and clones into the very directory clone_monkey_project
# would have used — one clone per run, not two.
PROJECT=monkey-env
PROJECT_REPO=https://github.com/QMonkey/monkey-env.git
INSTALL_DIR="${INSTALL_DIR:-$HOME/Documents/monkey-env}"

# No scripts/ next to this file: either a checkout predating the subtree
# commit (pull it in and carry on) or `curl | bash`, which has no checkout
# at all. The latter clones THIS project and runs the install.sh from that
# checkout, so installer and scripts/ always come from the same revision.
_monkey_scripts="$(dirname "${BASH_SOURCE[0]:-$0}")/scripts"
if [ ! -f "$_monkey_scripts/install.sh" ]; then
	_monkey_self="${BASH_SOURCE[0]:-$0}"
	_monkey_dir="$(dirname "$_monkey_self")"
	if [ -f "$_monkey_self" ] && [ -d "$_monkey_dir/.git" ]; then
		git -C "$_monkey_dir" pull --ff-only || true
		_monkey_scripts="$_monkey_dir/scripts"
		if [ ! -f "$_monkey_scripts/install.sh" ]; then
			echo "monkey-scripts missing from $_monkey_dir (no scripts/ subtree)." >&2
			echo "  git -C $_monkey_dir pull    # outdated checkout — or the repo never added the subtree" >&2
			exit 1
		fi
	else
		# curl|bash: no checkout at all. Get one that carries scripts/ and
		# hand over to its installer, so install.sh and scripts/ can never be
		# different revisions. clone_monkey_project cannot do this job — it
		# lives in the very scripts/ being fetched. INSTALL_DIR is where the
		# framework's clone step would have put the checkout too, so that step
		# only confirms it.
		if ! command -v git >/dev/null 2>&1; then
			echo "git is required to clone $PROJECT — install it first (e.g. sudo apt-get install git), then re-run." >&2
			exit 1
		fi
		if [ -d "$INSTALL_DIR/.git" ]; then
			# An install already lives here: update it, then run that one.
			git -C "$INSTALL_DIR" pull --ff-only || true
		elif [ -d "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR")" ]; then
			# git clone would refuse too, so say why in our own words.
			echo "$INSTALL_DIR is not empty and is not a git clone." >&2
			echo "  move it aside, delete it, or set INSTALL_DIR elsewhere." >&2
			exit 1
		else
			# No retry() available yet — the framework loads only after this
		# clone succeeds — so inline the standard 3 attempts. A failed clone
		# leaves a partial directory behind; remove it so the next attempt
		# cannot trip over "already exists". This branch only runs on a
		# fresh install (INSTALL_DIR did not exist or was empty), so the rm
		# can never delete pre-existing data.
		_monkey_rc=1
		for _monkey_attempt in 1 2 3; do
			if git clone "$PROJECT_REPO" "$INSTALL_DIR"; then
				_monkey_rc=0
				break
			fi
			rm -rf "$INSTALL_DIR"
			if [ "$_monkey_attempt" -lt 3 ]; then
				sleep 2
			fi
		done
		[ "$_monkey_rc" -eq 0 ] || exit 1
		fi
		# </dev/null: on the curl|bash path stdin is the script pipe, and the
		# inner installer must not read what is left of the outer one.
		exec bash "$INSTALL_DIR/install.sh" "$@" </dev/null
	fi
fi
# shellcheck source=/dev/null
. "$_monkey_scripts/install.sh"

# ──────────────────────── component chain ────────────────────────

# Canonical --with-* projection order — kmscon (a local setup step, not a
# downloaded component) first, then outer environment, editors last. At
# runtime monkey-zsh and monkey-wezterm are hoisted to the front (see parse_args).
ALL_COMPONENTS=(kmscon monkey-hyprland monkey-sway monkey-wezterm monkey-tmux monkey-zsh monkey-nvim monkey-vim)
# Default selection when no --with-* flag is given: everything EXCEPT
# monkey-sway (opt-in — a second Wayland desktop; installing both is fine,
# the last install wins the shared ~/.config/waybar link). On platforms
# where a Wayland desktop config is not applicable (WSL, macOS) the default
# also drops monkey-hyprland — see parse_args.
DEFAULT_COMPONENTS=(monkey-hyprland monkey-wezterm monkey-tmux monkey-zsh monkey-nvim monkey-vim)

COMPONENTS=()
SUCCEEDED_COMPONENTS=()
FAILED_COMPONENTS=()
WITH_KMSCON=""

# ──────────────────────── selection ────────────────────────

usage() {
	cat <<EOF
Usage: $0 [OPTIONS]

One-shot meta-installer for the monkey-* family. Installs the component
configs in dependency order: wezterm -> hyprland -> sway -> tmux -> nvim ->
vim (monkey-zsh runs first so its login-shell switch precedes the other
components' profile writes; wezterm precedes the compositors because both
treat it as their default terminal; monkey-sway is opt-in).

OPTIONS
  --with-monkey-hyprland  Include the Hyprland desktop config
  --with-monkey-sway      Include the sway desktop config (opt-in)
  --with-monkey-wezterm   Include the wezterm config
  --with-monkey-tmux      Include the tmux config
  --with-monkey-zsh       Include the zsh config
  --with-monkey-nvim      Include the nvim config
  --with-monkey-vim       Include the vim config
                          Multiple --with-* flags combine; the install order
                          is always zsh first, then wezterm -> hyprland ->
                          sway -> tmux -> nvim -> vim. Without any
                          --with-* flag, everything installs EXCEPT
                          monkey-sway — and on WSL/macOS also EXCEPT
                          monkey-hyprland (pass --with-monkey-hyprland to
                          install it there anyway).
  --with-kmscon [tty[,tty...]]
                          Enable the kmscon console on the given VTs
                          (default tty2): installs kmscon, enables
                          kmscon@ttyN and masks getty@ttyN there; the
                          bare getty stays on every other VT as the
                          last-resort console. Handled by this installer
                          itself — not forwarded to components — and
                          selected like any other --with-* entry: given
                          alone, only the kmscon setup runs (headless
                          console); combined with component flags it is
                          additive and runs first. Setup failures never
                          abort the install: unsupported environments
                          (no systemd/KMS) are skipped with a warning. Given WITHOUT any --with-* component
                          flag, only the kmscon setup runs — no components
                          are installed (headless console).
  -h, --help              Show this help

Run it from a pipe (note the \`-s --\`, which forwards the flags past
bash's own option parsing):

  curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-env/master/install.sh | bash -s -- --with-monkey-tmux --with-monkey-zsh

Exit code: 1 if any component failed, 0 otherwise.
EOF
	exit 0
}

parse_args() {
	local with=() c w
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--with-monkey-hyprland) with+=("monkey-hyprland") ;;
		--with-monkey-sway) with+=("monkey-sway") ;;
		--with-monkey-wezterm) with+=("monkey-wezterm") ;;
		--with-monkey-tmux) with+=("monkey-tmux") ;;
		--with-monkey-zsh) with+=("monkey-zsh") ;;
		--with-monkey-nvim) with+=("monkey-nvim") ;;
		--with-monkey-vim) with+=("monkey-vim") ;;
		--with-kmscon)
			with+=("kmscon")
			WITH_KMSCON=tty2
			if [[ $# -gt 1 && "$2" != --* ]]; then
				WITH_KMSCON=$2
				shift
			fi
			;;
		-h | --help) usage ;;
		*)
			echo "Unknown option: $1"
			usage
			;;
		esac
		shift
	done
	if [[ ${#with[@]} -gt 0 ]]; then
		# Re-project the selection onto the canonical order, whatever order
		# the flags came in, and deduplicate.
		for c in "${ALL_COMPONENTS[@]}"; do
			for w in "${with[@]}"; do
				if [ "$w" = "$c" ]; then
					COMPONENTS+=("$c")
					break
				fi
			done
		done
	else
		# Default: everything EXCEPT monkey-sway (opt-in). On WSL or macOS
		# a Wayland desktop config is not applicable (WSL has no VT login —
		# XDG_VTNR is never set, so the guarded autostart block stays
		# inert; WSLg already renders single GUI apps) — drop hyprland
		# from the default too. An explicit --with-monkey-hyprland still
		# installs it.
		COMPONENTS=("${DEFAULT_COMPONENTS[@]}")
		if [ "$(uname -s)" != "Linux" ] || is_wsl; then
			local rest_default=() c3
			for c3 in "${COMPONENTS[@]}"; do
				[ "$c3" = "monkey-hyprland" ] || rest_default+=("$c3")
			done
			COMPONENTS=("${rest_default[@]}")
		fi
	fi
	local has_zsh=0 has_wezterm=0 rest=() c2
	for c2 in "${COMPONENTS[@]}"; do
		case "$c2" in
		monkey-zsh) has_zsh=1 ;;
		monkey-wezterm) has_wezterm=1 ;;
		*) rest+=("$c2") ;;
		esac
	done
	if [[ ${#rest[@]} -lt ${#COMPONENTS[@]} ]]; then
		COMPONENTS=()
		[ "$has_zsh" -eq 1 ] && COMPONENTS+=("monkey-zsh")
		[ "$has_wezterm" -eq 1 ] && COMPONENTS+=("monkey-wezterm")
		if [[ ${#rest[@]} -gt 0 ]]; then
			COMPONENTS+=("${rest[@]}")
		fi
	fi
}

# ──────────────────────── components ────────────────────────

# The kmscon "component": a local setup step, not a downloaded repo — it
# runs ensure_kmscon from the shared framework. Its selection semantics are
# identical to the other --with-* entries (see parse_args); the WSL/macOS
# guard lives here because that is where the setup would run.
run_kmscon() {
	if [ "$(uname -s)" != "Linux" ] || is_wsl; then
		warn "kmscon is not applicable on WSL/macOS — skipping."
		return 0
	fi
	ensure_kmscon "$WITH_KMSCON"
}

run_component() {
	local name="$1"
	info "──────────────── Installing ${BOLD}$name${NC}${CYAN} ────────────────"
	if [ "$name" = kmscon ]; then
		if run_kmscon; then
			ok "$name set up."
			SUCCEEDED_COMPONENTS+=("$name")
		else
			FAILED_COMPONENTS+=("$name")
			warn "$name setup failed — continuing with the remaining components."
		fi
		return 0
	fi
	local url="https://raw.githubusercontent.com/QMonkey/$name/master/install.sh"
	# Downloaded fully before executing, with retries: `curl | bash` would
	# run a truncated script if the connection drops mid-stream (and a
	# retry could then re-run the partial script from the top). The file
	# also keeps stdin clean — the component gets /dev/null, the same as
	# its own curl|bash bootstrap hands its inner installer, so nothing
	# consumes this script's own piped source.
	local installer="/tmp/${name}_install.$$.sh"
	if retry -s "$name installer download" curl -fsSL "$url" -o "$installer"; then
		if bash "$installer" </dev/null; then
			ok "$name installed."
			SUCCEEDED_COMPONENTS+=("$name")
		else
			FAILED_COMPONENTS+=("$name")
			warn "$name install failed — continuing with the remaining components."
		fi
		rm -f "$installer"
	else
		FAILED_COMPONENTS+=("$name")
		warn "$name installer download failed — continuing with the remaining components."
	fi
	# Re-expose the tool locations components install to — Homebrew, cargo
	# and go — so later components find them instead of re-downloading.
	# Direct PATH exports rather than sourcing the profiles: this shell
	# only needs the tool paths, not the profiles' arbitrary user code
	# (inits, hooks). The case guards keep PATH idempotent across
	# components. Two tiers, mirroring _preseed_path: user whitelist dirs
	# at the FRONT, Homebrew APPENDED at the back — brew's binaries must
	# not shadow the system's (its python@3.x hid /usr/bin/python3).
	local d
	for d in "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/go/bin" "$HOME/.npm-global/bin"; do
		[ -d "$d" ] || continue
		case ":$PATH:" in *":$d:"*) ;; *) export PATH="$d:$PATH" ;; esac
	done
	for d in /home/linuxbrew/.linuxbrew/bin /opt/homebrew/bin; do
		[ -d "$d" ] || continue
		path_add_pre_win "$d"
	done
	return 0
}

run_components() {
	local c
	for c in "${COMPONENTS[@]}"; do
		echo ""
		run_component "$c"
	done
}

# ────────────────── current-terminal activation ──────────────────
# Components skipped their own injection (ACQUIRE_TIOCSTI protocol) —
# inject once here, after the whole chain has finished. The login shell
# decides which profile holds every component's env blocks (all blocks
# are dedup'd, so sourcing any one of them is complete and idempotent).
inject_current_terminal() {
	local shell_bin env_file
	if [ "$(uname -s)" = "Darwin" ]; then
		shell_bin="$(dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | awk '{print $NF}')"
	else
		shell_bin="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
	fi
	case "$shell_bin" in
	*/zsh) env_file="$HOME/.zprofile" ;;
	*/bash)
		if [ -f "$HOME/.bash_profile" ]; then
			env_file="$HOME/.bash_profile"
		else
			env_file="$HOME/.profile"
		fi
		;;
	*)
		warn "could not determine the login shell — no terminal injection."
		return 0
		;;
	esac
	[ -f "$env_file" ] || {
		warn "$env_file not found — no terminal injection."
		return 0
	}
	if [ "$ACQUIRE_TIOCSTI" = "monkey-env" ] && inject_tty "source ${env_file}"; then
		ok "injected 'source ${env_file}' into the current terminal."
	else
		warn "could not inject into the current terminal — run: source ${env_file}"
	fi
}

print_summary() {
	echo ""
	if [[ ${#FAILED_COMPONENTS[@]} -eq 0 ]]; then
		echo -e "${GREEN}${BOLD}All components installed successfully.${NC}"
		echo ""
		echo -e "  Start a new shell to pick up the PATH changes (${CYAN}exec zsh${NC} or reopen the terminal),"
		echo -e "  then run each component's ${CYAN}checkhealth.sh${NC} for a per-component report."
		exit 0
	fi
	if [[ ${#SUCCEEDED_COMPONENTS[@]} -gt 0 ]]; then
		echo -e "${GREEN}Installed successfully:${NC} ${SUCCEEDED_COMPONENTS[*]}"
	fi
	echo -e "${RED}${BOLD}Failed: ${FAILED_COMPONENTS[*]}${NC}"
	echo -e "Re-run the installer (it is idempotent) or install the failed ones individually:"
	local c
	for c in "${FAILED_COMPONENTS[@]}"; do
		echo -e "  ${CYAN}curl -fsSL https://raw.githubusercontent.com/QMonkey/$c/master/install.sh | bash${NC}"
	done
	exit 1
}

# ──────────────────── main ────────────────────
# Custom flow: no install_main() here — the chain, its banner section and
# the single end-of-chain injection are this file's own.

main() {
	parse_args "$@"

	# TIOCSTI injection right: components inherit this and skip their own
	# injection — this chain injects ONCE, here, after everything exits.
	export ACQUIRE_TIOCSTI="${ACQUIRE_TIOCSTI:-monkey-env}"

	# Every component installer is fetched with curl and clones its own repo
	# with git — both are hard prerequisites of the whole chain. Fail fast
	# with an actionable message instead of letting every component's
	# bootstrap die with a confusing per-component error.
	have_native_cmd git ||
		fail "git is required to clone the component repositories — install it first (e.g. sudo apt-get install git), then re-run."
	have_native_cmd curl ||
		fail "curl is required to fetch the component installers — install it first (e.g. sudo apt-get install curl), then re-run."

	print_banner "${PROJECT} installer"
	local c
	echo -e "${BOLD}Components (in install order)${NC}"
	for c in "${COMPONENTS[@]}"; do
		echo -e "  ${CYAN}$c${NC}"
	done
	echo ""

	setup_sudo

	run_components

	inject_current_terminal

	print_summary
}

main "$@"
