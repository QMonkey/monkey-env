#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# monkey-env one-shot meta-installer
#
# Chains the monkey-* component installers in dependency order:
#   monkey-wezterm -> monkey-tmux -> monkey-zsh -> monkey-nvim -> monkey-vim
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-env/main/install.sh | bash -s -- [OPTIONS]
#   bash install.sh [OPTIONS]
#
# NOTE: `bash --with-monkey-tmux` does NOT work — bash would parse it as
# its own option. `bash -s --` ends bash's option parsing and forwards
# everything after `--` to this script as positional parameters.
# ──────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SUDOERS_D_DIR="${SUDOERS_D_DIR:-/etc/sudoers.d}"
SUDO_NOPASSWD=0
NOPASSWD_DROPIN="$SUDOERS_D_DIR/zz-monkey-env-nopasswd"

# Canonical install order — outer environment first, editors last.
ALL_COMPONENTS=(monkey-wezterm monkey-tmux monkey-zsh monkey-nvim monkey-vim)
# Not supported yet (their installers do not exist): monkey-hyprland, monkey-sway.

COMPONENTS=()
FAILED_COMPONENTS=()

info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[  OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() {
	echo -e "${RED}[FAIL]${NC}  $*"
	exit 1
}

usage() {
	cat <<EOF
Usage: $0 [OPTIONS]

One-shot meta-installer for the monkey-* family. Installs the component
configs in dependency order: wezterm -> tmux -> zsh -> nvim -> vim.

OPTIONS
  --with-monkey-wezterm   Include the wezterm config
  --with-monkey-tmux      Include the tmux config
  --with-monkey-zsh       Include the zsh config
  --with-monkey-nvim      Include the nvim config
  --with-monkey-vim       Include the vim config
                          Multiple --with-* flags combine; the install order
                          is always wezterm -> tmux -> zsh -> nvim -> vim.
                          Without any --with-* flag, ALL of the above install.
  -h, --help              Show this help

Run it from a pipe (note the \`-s --\`, which forwards the flags past
bash's own option parsing):

  curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-env/main/install.sh | bash -s -- --with-monkey-tmux --with-monkey-zsh

Exit code: 1 if any component failed, 0 otherwise.
EOF
	exit 0
}

parse_args() {
	local with=() c w
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--with-monkey-wezterm) with+=("monkey-wezterm") ;;
		--with-monkey-tmux) with+=("monkey-tmux") ;;
		--with-monkey-zsh) with+=("monkey-zsh") ;;
		--with-monkey-nvim) with+=("monkey-nvim") ;;
		--with-monkey-vim) with+=("monkey-vim") ;;
		--with-monkey-hyprland | --with-monkey-sway)
			fail "$1 is not supported yet — its installer does not exist."
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
		COMPONENTS=("${ALL_COMPONENTS[@]}")
	fi
}

# ──────────────────────────── sudo setup ────────────────────────────
# The meta-installer holds ONE temporary NOPASSWD grant for the whole
# chain: without it, every component installer would ask for the password
# separately (five prompts). With it, each component's own `sudo -v`
# succeeds silently and their per-component drop-ins become redundant but
# harmless. Removed on exit.

SUDO_BIN=""

cleanup_sudo() {
	if [ "$SUDO_NOPASSWD" -eq 1 ] && [ -n "$SUDO_BIN" ]; then
		"$SUDO_BIN" -n rm -f "$NOPASSWD_DROPIN" 2>/dev/null ||
			warn "could not remove the NOPASSWD drop-in — remove it manually: sudo rm $NOPASSWD_DROPIN"
	fi
}

setup_sudo() {
	SUDO_BIN=$(native_sudo) || return 0
	if [ "$(id -u)" -eq 0 ]; then
		return 0
	fi
	# The only password entry of the whole chain.
	"$SUDO_BIN" -v || fail "sudo authorization failed — run this script in an interactive terminal."
	if printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$(id -un)" |
		"$SUDO_BIN" -n sh -c 'umask 077; cat >"$1" && chmod 0440 "$1" && visudo -c -f "$1" >/dev/null 2>&1 || { rm -f "$1"; exit 1; }' sh "$NOPASSWD_DROPIN" >/dev/null 2>&1; then
		SUDO_NOPASSWD=1
		ok "Temporary NOPASSWD drop-in installed for this run (auto-removed on exit)."
	else
		warn "could not install the temporary NOPASSWD drop-in — each component will ask for the password separately."
	fi
	trap cleanup_sudo EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
}

# Absolute path to a LINUX sudo, or non-zero. Windows 11 ships an optional
# sudo.exe that WSL interop exposes as /mnt/.../sudo.exe — running it from
# WSL would be meaningless.
native_sudo() {
	local p
	have_native_cmd sudo || return 1
	p=$(command -v sudo)
	printf '%s' "$p"
}

# WSL interop appends the WINDOWS PATH to ours, so tools installed on the
# Windows side appear as /mnt/c/... shims. They are not Linux binaries.
have_native_cmd() {
	command -v "$1" &>/dev/null || return 1
	case "$(command -v "$1")" in
	/mnt/*) return 1 ;; # WSL Windows-interop shim
	esac
	return 0
}

# ──────────────────────────── components ────────────────────────────

run_component() {
	local name="$1"
	local url="https://raw.githubusercontent.com/QMonkey/$name/master/install.sh"
	info "──────────────── Installing ${BOLD}$name${NC}${CYAN} ────────────────"
	# `</dev/null` guards this script's own stdin (the piped source) from
	# being consumed by anything the component runs; sudo prompts go to
	# /dev/tty and never touch stdin.
	if curl -fsSL "$url" | bash; then
		ok "$name installed."
		return 0
	fi
	FAILED_COMPONENTS+=("$name")
	warn "$name install failed — continuing with the remaining components."
	return 0
}

run_components() {
	local c
	for c in "${COMPONENTS[@]}"; do
		echo ""
		run_component "$c"
	done
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
	echo -e "${RED}${BOLD}Some components failed: ${FAILED_COMPONENTS[*]}${NC}"
	echo -e "Re-run the installer (it is idempotent) or install them individually:"
	local c
	for c in "${COMPONENTS[@]}"; do
		echo -e "  ${CYAN}curl -fsSL https://raw.githubusercontent.com/QMonkey/$c/master/install.sh | bash${NC}"
	done
	exit 1
}

# ──────────────────── main ────────────────────

main() {
	parse_args "$@"

	echo ""
	echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
	echo -e "${BOLD}║       monkey-env installer               ║${NC}"
	echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
	echo ""
	local c
	echo -e "${BOLD}Components (in install order)${NC}"
	for c in "${COMPONENTS[@]}"; do
		echo -e "  ${CYAN}$c${NC}"
	done
	echo ""

	setup_sudo

	run_components

	cleanup_sudo

	print_summary
}

main "$@"
