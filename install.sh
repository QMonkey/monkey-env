#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# monkey-env one-shot meta-installer
#
# Chains the monkey-* component installers in dependency order:
#   monkey-zsh -> monkey-wezterm -> monkey-hyprland -> monkey-sway ->
#   monkey-tmux -> monkey-nvim -> monkey-vim -> monkey-agent
#   (runtime order: monkey-zsh and monkey-wezterm are hoisted to the
#   front — zsh's chsh must precede the later stages so their env blocks
#   land in ~/.zprofile; wezterm precedes the compositors because both
#   checkhealth scripts treat it as their default terminal and would
#   otherwise install it themselves, bypassing this component's source build.
#   monkey-agent runs last — it is tooling on top of every other component.
#   monkey-sway is opt-in: --with-monkey-sway.
#   Default installs everything else, including monkey-hyprland — except
#   on WSL/macOS, where the default drops monkey-hyprland as well;
#   --with-monkey-hyprland overrides.)
#
# kmscon is not a component but a local SYSTEM-LEVEL setup step (install
# the package, write the unit/PAM bits, enable kmscon@ttyN and mask
# getty@ttyN — masking only up to tty6, the range where a default getty
# exists at all) selected with --with-kmscon [tty[,tty...]]. It always runs
# FIRST — before any component: it depends on nothing but sudo (granted
# by setup_sudo) and the package manager, no component depends on it, and
# running it before the user-config steps means a VT takeover is already
# in place no matter how far the chain gets. On WSL/macOS it is skipped
# with a warning. Given without any component flag, only the kmscon
# setup runs (headless console).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-env/master/install.sh | bash 2>&1 | tee monkey-env-install.log
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
# its own scripts/, so both come from the same revision. The chain runs as
# install_main's tool step; the banner, the dependency pass, the completion
# report and the terminal injection are the framework's, exactly as in any
# component installer.
# ──────────────────────────────────────────────────────────────

# ──────────────────────── repository identity ────────────────────────
# Declared before the framework is sourced: the bootstrap below needs
# both values, and clones into the very directory clone_project
# would have used — one clone per run, not two.
PROJECT=monkey-env
PROJECT_REPO=https://github.com/QMonkey/monkey-env.git
INSTALL_DIR="${INSTALL_DIR:-$HOME/Documents/monkey-env}"

# No scripts/ next to this file: either a checkout predating the subtree
# commit (pull it in and carry on), a .git-less directory (zip/tarball),
# or `curl | bash`, which has no checkout at all. The latter two bootstrap
# through INSTALL_DIR and run the install.sh from that checkout, so
# installer and scripts/ always come from the same revision.
_monkey_scripts="$(dirname "${BASH_SOURCE[0]:-$0}")/scripts"
if [ ! -f "$_monkey_scripts/install.sh" ]; then
	_monkey_self="${BASH_SOURCE[0]:-$0}"
	_monkey_dir="$(dirname "$_monkey_self")"
	if [ -f "$_monkey_self" ] && [ -d "$_monkey_dir/.git" ]; then
		# Outdated checkout: update it in place and keep running from it.
		git -C "$_monkey_dir" pull --ff-only || true
		if [ ! -f "$_monkey_dir/scripts/install.sh" ]; then
			printf '%s\n' "monkey-scripts missing from $_monkey_dir (no scripts/ subtree)." >&2
			printf '%s\n' "  git -C $_monkey_dir pull    # outdated checkout — or the repo never added the subtree" >&2
			exit 1
		fi
		_monkey_scripts="$_monkey_dir/scripts"
	else
		# curl|bash or a .git-less directory: the only path to a
		# same-revision scripts/ is the INSTALL_DIR checkout.
		# clone_project cannot do this job — it lives in the very
		# scripts/ being fetched. INSTALL_DIR is where the framework's clone
		# step would have put the checkout too, so that step only confirms it.
		if [ -d "$INSTALL_DIR/.git" ]; then
			git -C "$INSTALL_DIR" pull --ff-only || true
		elif [ -d "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR")" ]; then
			# git clone would refuse too, so say why in our own words.
			printf '%s\n' "$INSTALL_DIR is not empty and is not a git clone." >&2
			printf '%s\n' "  move it aside, delete it, or set INSTALL_DIR elsewhere." >&2
			exit 1
		else
			# Fresh clone — the ONLY sub-branch where git is hard-required:
			# the pull sub-branch above degrades gracefully without it, and
			# a zip/tarball must not fail here just for a missing git.
			if ! command -v git >/dev/null 2>&1; then
				printf '%s\n' "git is required to clone $PROJECT — install it first (e.g. sudo apt-get install git), then re-run." >&2
				exit 1
			fi
			# No retry() available yet — the framework loads only after this
			# clone succeeds — so inline a bounded retry loop by hand. A failed
			# clone leaves a partial directory behind; remove it so the next
			# attempt cannot trip over "already exists". This branch only
			# runs on a fresh install (INSTALL_DIR did not exist or was
			# empty), so the rm can never delete pre-existing data.
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
ALL_COMPONENTS=(kmscon monkey-hyprland monkey-sway monkey-wezterm monkey-tmux monkey-zsh monkey-nvim monkey-vim monkey-agent)
# Default selection when no --with-* flag is given: everything EXCEPT
# monkey-sway (opt-in — a second Wayland desktop; installing both is fine, each
# desktop reads its own waybar dir: ~/.config/hypr/waybar and
# ~/.config/sway/waybar). On platforms where a Wayland desktop config is not
# applicable (WSL, macOS) the default
# also drops monkey-hyprland — see parse_args. monkey-agent is default-on
# (plain shell tooling, applicable everywhere); --with-monkey-agent exists
# for explicitness only — selecting it is a no-op relative to the default.
DEFAULT_COMPONENTS=(monkey-hyprland monkey-wezterm monkey-tmux monkey-zsh monkey-nvim monkey-vim monkey-agent)

COMPONENTS=()
SUCCEEDED_COMPONENTS=()
FAILED_COMPONENTS=()

# ──────────────────────── selection ────────────────────────

usage() {
	cat <<EOF
Usage: $0 [OPTIONS]

One-shot meta-installer for the monkey-* family. Installs the component
configs in dependency order: wezterm -> hyprland -> sway -> tmux -> nvim ->
vim -> agent (zsh runs first so its login-shell switch precedes the
other components' profile writes; wezterm precedes the compositors because
both treat it as their default terminal; sway is opt-in; the agent tooling
runs last — it is tooling layered on top of the other components).

OPTIONS
  --with-monkey-hyprland  Include the Hyprland desktop config
  --with-monkey-sway      Include the sway desktop config (opt-in)
  --with-monkey-wezterm   Include the wezterm config
  --with-monkey-tmux      Include the tmux config
  --with-monkey-zsh       Include the zsh config
  --with-monkey-nvim      Include the nvim config
  --with-monkey-vim       Include the vim config
  --with-monkey-agent     Include the monkey-agent tooling (default on —
                          this flag exists for explicitness only)
                          Multiple --with-* flags combine; the install order
                          is always zsh first, then wezterm -> hyprland ->
                          sway -> tmux -> nvim -> vim -> agent. Without any
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

  curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-env/master/install.sh | bash -s -- --with-monkey-tmux --with-monkey-zsh 2>&1 | tee monkey-env-install.log

Exit code: 1 if any component failed, 0 otherwise.
EOF
	exit 0
}

parse_args() {
	# --with-kmscon belongs to the framework's parser: its arm is the very same
	# "default tty2, swallow one non-flag value" rule this file used to carry
	# twice. Whatever it leaves in _INSTALL_ARGS is this file's own selection.
	parse_install_args "$@"
	set -- ${_INSTALL_ARGS[@]+"${_INSTALL_ARGS[@]}"}
	local with=() c w
	if [ -n "$KMSCON_TTYS" ]; then
		with+=("kmscon")
	fi
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--with-monkey-hyprland) with+=("monkey-hyprland") ;;
		--with-monkey-sway) with+=("monkey-sway") ;;
		--with-monkey-wezterm) with+=("monkey-wezterm") ;;
		--with-monkey-tmux) with+=("monkey-tmux") ;;
		--with-monkey-zsh) with+=("monkey-zsh") ;;
		--with-monkey-nvim) with+=("monkey-nvim") ;;
		--with-monkey-vim) with+=("monkey-vim") ;;
		--with-monkey-agent) with+=("monkey-agent") ;;
		-h | --help) usage ;;
		*)
			printf '%s\n' "Unknown option: $1"
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
		# On WSL or a non-Linux host a Wayland desktop config is not
		# applicable — WSL logins are ptys, so the autostart block's
		# /dev/ttyN guard never matches (and WSLg already renders single
		# GUI apps) — drop hyprland from the default too. An explicit
		# --with-monkey-hyprland still installs it.
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

# The kmscon "component" is a local setup step, not a downloaded repo — it
# runs ensure_kmscon from the shared framework, on the tty list the
# framework's own parser filled. Its selection semantics are identical to the
# other --with-* entries (see parse_args); the non-Linux / WSL / no-systemd /
# no-KMS guards live in ensure_kmscon itself (warn + skip = success).
run_component() {
	local name="$1"
	info "──────────────── Installing ${BOLD}$name${NC}${CYAN} ────────────────"
	if [ "$name" = kmscon ]; then
		if ensure_kmscon "$KMSCON_TTYS"; then
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
	# fetch_url_or_clone falls back to a shallow clone of the component
	# repository when the CDN is unreachable: raw.githubusercontent.com
	# went down for minutes at a time while github.com git endpoints still
	# responded — every component whose installer lived behind that CDN was lost to the failure.
	local installer="/tmp/${name}_install.$$.sh"
	if fetch_url_or_clone "$url" "https://github.com/QMonkey/$name.git" "$installer" "$name installer"; then
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
	# Re-expose the tool locations components install to — Homebrew, cargo,
	# go and npm — so later components find them instead of re-downloading.
	# export_path (lib/env.sh) owns the two-tier ordering — user whitelist
	# dirs at the FRONT, Homebrew prepended on macOS and positionally
	# inserted (ahead of the WSL /mnt/* shims only) on Linux — and is
	# idempotent, so repeated calls across components are safe.
	export_path
	return 0
}

run_components() {
	local c
	for c in "${COMPONENTS[@]}"; do
		printf '\n'
		run_component "$c"
	done
}

# The chain holds the TIOCSTI right (ACQUIRE_TIOCSTI below equals PROJECT), so
# finish_install — not any component — performs the single end-of-run
# injection: the XDG_RUNTIME_DIR fix first, then `source <profile>`. That is
# the same code path a component uses when installed alone, so the chain can
# no longer drift from it.
queue_chain_verdict() {
	local c
	if [[ ${#FAILED_COMPONENTS[@]} -eq 0 ]]; then
		SUMMARY_LINES+=("${GREEN}${BOLD}All components installed successfully.${NC}")
		return 0
	fi
	if [[ ${#SUCCEEDED_COMPONENTS[@]} -gt 0 ]]; then
		SUMMARY_LINES+=("${GREEN}Installed successfully:${NC} ${SUCCEEDED_COMPONENTS[*]}")
	fi
	SUMMARY_LINES+=("${RED}${BOLD}Failed: ${FAILED_COMPONENTS[*]}${NC}")
	SUMMARY_LINES+=("Re-run the installer (it is idempotent) or install the failed ones individually:")
	for c in "${FAILED_COMPONENTS[@]}"; do
		SUMMARY_LINES+=("  ${CYAN}curl -fsSL https://raw.githubusercontent.com/QMonkey/$c/master/install.sh | bash 2>&1 | tee $c-install.log${NC}")
	done
	return 0
}

# ──────────────────── framework hooks ────────────────────
# The consumer shape: identity and data above, install_main at the bottom.
# The chain is what install_step_tool runs; the banner, the sudo grant, the
# dependency pass, the completion report and the terminal injection all come
# from the framework, so there is one implementation of each here and in every
# component installer.

install_print_info() {
	printf '%s\n' "${BOLD}Components (in install order)${NC}"
	local c
	for c in "${COMPONENTS[@]}"; do
		printf '%s\n' "  ${CYAN}$c${NC}"
	done
	printf '\n'
}

install_step_prepare() {
	# Every component installer is fetched with curl and clones its own repo
	# with git, so both are hard prerequisites of the chain — and the hooks run
	# before install_main's own dependency pass (install_main:186-193), so they
	# have to be secured here first. "vcs" IS that pair in the framework's
	# build-group table (git + curl; macOS ships curl), the same verb every
	# component reaches for early — this chain borrows nothing special.
	# ensure_git then hard-stops with the distro hint when the install could
	# not deliver it, and the framework's pass stays the plain verification it
	# is for every other project.
	export ACQUIRE_TIOCSTI="${ACQUIRE_TIOCSTI:-monkey-env}"
	install_build_deps vcs
	ensure_git
	have_native_cmd curl ||
		fail "curl is required to fetch the component installers — install it first: $(get_install_hint curl)"
}

install_step_tool() {
	run_components
	printf '\n'
}

# Last hook before finish_install prints these lines and injects.
install_step_after() {
	queue_chain_verdict
}

# ──────────────────── entry ────────────────────
# parse_args owns --with-monkey-* and delegates --with-kmscon to the
# framework's parser (see there). install_main ends with finish_install, so
# the verdict and the injection are already printed by the time this exit
# runs — and it must stay an `if`: as the file's last command, a trailing
# `[ … ] && exit 1` would itself yield status 1 on the all-good path.
parse_args "$@"
install_main
if [[ ${#FAILED_COMPONENTS[@]} -gt 0 ]]; then
	exit 1
fi
