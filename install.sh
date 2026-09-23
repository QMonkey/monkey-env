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

# Canonical --with-* projection order — outer environment first, editors
# last. At runtime monkey-zsh and monkey-wezterm are hoisted to the front (see parse_args).
ALL_COMPONENTS=(monkey-hyprland monkey-sway monkey-wezterm monkey-tmux monkey-zsh monkey-nvim monkey-vim)
# Default selection when no --with-* flag is given: everything EXCEPT
# monkey-sway (opt-in — a second Wayland desktop; installing both is fine,
# the last install wins the shared ~/.config/waybar link). On platforms
# where a Wayland desktop config is not applicable (WSL, macOS) the default
# also drops monkey-hyprland — see parse_args.
DEFAULT_COMPONENTS=(monkey-hyprland monkey-wezterm monkey-tmux monkey-zsh monkey-nvim monkey-vim)

COMPONENTS=()
SUCCEEDED_COMPONENTS=()
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

# ──────────────────────────── sudo setup ────────────────────────────
# The meta-installer holds ONE temporary NOPASSWD grant for the whole
# chain: without it, every component installer would ask for the password
# separately (five prompts). With it, each component's own `sudo -v`
# succeeds silently and their per-component drop-ins become redundant but
# harmless. Removed on exit.

SUDO_BIN=""

cleanup_sudo() {
	# Flag cleared BEFORE acting: main() calls this explicitly and the EXIT
	# trap calls it again on the way out. The second pass must be a no-op —
	# once the grant file is gone, `sudo -n rm` can no longer authenticate
	# (no timestamp is ever recorded because every sudo during the run was
	# NOPASSWD), and it would warn even though the file was already removed.
	if [ "$SUDO_NOPASSWD" -eq 1 ] && [ -n "$SUDO_BIN" ]; then
		SUDO_NOPASSWD=0
		"$SUDO_BIN" -n rm -f "$NOPASSWD_DROPIN" 2>/dev/null ||
			warn "could not remove the NOPASSWD drop-in — remove it manually: sudo rm $NOPASSWD_DROPIN"
	fi
}

setup_sudo() {
	SUDO_BIN=$(native_sudo) || return 0
	if [ "$(id -u)" -eq 0 ]; then
		return 0
	fi
	# Pre-authenticate — the only password entry of the whole chain — then
	# grant NOPASSWD for the rest of it:
	#
	# Probe first (`-n true`, a command): when credentials are already
	# valid — this run's own drop-in from a previous stage, or an outer
	# installer's grant — skip the authenticate step entirely; chained
	# stages never re-prompt. Failure means no valid grant exists and
	# `sudo -v` prompts for the one password of the run.
	#
	# Why the drop-in is NOPASSWD: authentication is granted by the rule
	# itself and the timestamp is never consulted, so brew's
	# --reset-timestamp, clock jumps and plain expiry are all harmless.
	# GNU sudo resolves conflicting rules last-match-wins, so this drop-in
	# (parsed after the distro's password-required rule) always wins.
	# sudo-rs would defeat this tag for VALIDATE (max_by_key picks the
	# password-required rule) — but every sudo in this script is a command
	# or the probe, where NOPASSWD wins on both implementations.
	if ! "$SUDO_BIN" -n true 2>/dev/null; then
		"$SUDO_BIN" -v || fail "sudo authorization failed — run this script in an interactive terminal."
	fi
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

# True under WSL (1 or 2): both kernels carry "microsoft" in the release
# string (WSL1 "...-Microsoft", WSL2 "...-microsoft-standard-WSL2") — the
# check Microsoft's own docs use.
is_wsl() {
	case "$(uname -r)" in
	*[Mm]icrosoft*) return 0 ;;
	*) return 1 ;;
	esac
}

# ────────────────── TIOCSTI injection ──────────────────
# Type <cmd> + newline into the controlling terminal: the parent shell
# executes it as if the user had typed it — AFTER this script (and any
# wrapper chaining it) has fully exited, so injection can never disturb
# the run itself. Needs python3 or perl; any failure returns non-zero so
# callers can fall back to a printed hint. Never fatal.
inject_tty() {
	local cmd="$1" tiocsti
	[ -n "$cmd" ] || return 1
	# No writable controlling terminal (CI, nested pipes) — nothing to
	# inject into. access(W_OK) on /dev/tty fails with ENXIO when the
	# process has no controlling tty.
	[ -w /dev/tty ] || return 1
	# python3 first: termios.TIOCSTI carries the correct constant per
	# platform (Linux 0x5412, Darwin 0x80047412).
	if have_native_cmd python3; then
		python3 - "$cmd" <<'PYEOF' 2>/dev/null && return 0
import sys, os, fcntl, termios
cmd = sys.argv[1] + "\n"
try:
    fd = os.open("/dev/tty", os.O_WRONLY)
    ioctl = termios.TIOCSTI
except (OSError, AttributeError):
    sys.exit(1)
for ch in cmd:
    try:
        fcntl.ioctl(fd, ioctl, ord(ch))
    except OSError:
        sys.exit(1)
PYEOF
	fi
	# perl fallback: macOS ships /usr/bin/perl, Debian/Ubuntu perl-base is
	# Essential. TIOCSTI's value differs per platform.
	tiocsti=0x5412
	[ "$(uname -s)" = "Darwin" ] && tiocsti=0x80047412
	perl -e '
		my ($cmd, $tio) = @ARGV;
		open(my $tty, ">", "/dev/tty") or exit 1;
		for my $ch (split //, $cmd . "\n") {
			ioctl($tty, hex($tio), ord($ch)) or exit 1;
		}
	' "$cmd" "$tiocsti" 2>/dev/null && return 0
	return 1
}

# ──────────────────────────── components ────────────────────────────

run_component() {
	local name="$1"
	local url="https://raw.githubusercontent.com/QMonkey/$name/master/install.sh"
	info "──────────────── Installing ${BOLD}$name${NC}${CYAN} ────────────────"
	# The pipeline gives bash a fresh stdin (the component source itself),
	# so nothing the component runs can consume this script's own piped
	# source.
	if curl -fsSL "$url" | bash; then
		ok "$name installed."
		SUCCEEDED_COMPONENTS+=("$name")
	else
		FAILED_COMPONENTS+=("$name")
		warn "$name install failed — continuing with the remaining components."
	fi
	# Re-expose the tool locations components install to — Homebrew, cargo
	# and go — so later components find them instead of re-downloading.
	# Direct PATH exports rather than sourcing the profiles: this shell
	# only needs the tool paths, not the profiles' arbitrary user code
	# (inits, hooks). The case guards keep PATH idempotent across
	# components; adding an existing-but-empty dir to PATH is harmless.
	local d
	for d in /home/linuxbrew/.linuxbrew/bin /opt/homebrew/bin "$HOME/.cargo/bin" "$HOME/go/bin"; do
		[ -d "$d" ] || continue
		case ":$PATH:" in *":$d:"*) ;; *) export PATH="$d:$PATH" ;; esac
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

main() {
	parse_args "$@"

	# TIOCSTI injection right: components inherit this and skip their own
	# injection — this chain injects ONCE, here, after everything exits.
	export ACQUIRE_TIOCSTI="${ACQUIRE_TIOCSTI:-monkey-env}"

	# Every component installer is fetched with curl — without it the whole
	# chain cannot start. Fail with an actionable message instead of letting
	# each component die with a confusing "curl: command not found".
	have_native_cmd curl ||
		fail "curl is required to fetch the component installers — install it first (e.g. sudo apt-get install curl), then re-run."

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

	inject_current_terminal

	print_summary
}

main "$@"
