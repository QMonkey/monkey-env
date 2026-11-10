# monkey-env

One-shot meta-installer for the monkey-* family. Chains the component installers in dependency order with a single password entry:

```text
monkey-zsh -> monkey-wezterm -> monkey-hyprland -> monkey-sway -> monkey-tmux -> monkey-nvim -> monkey-vim -> monkey-agent
```

monkey-zsh runs first on purpose: it switches the login shell to zsh before anything else, so the env blocks the later components persist land in `~/.zprofile` (which zsh reads) instead of `.profile`.

monkey-wezterm runs before the compositors on purpose: both desktop configs treat WezTerm as their default terminal and would otherwise try to install it themselves, bypassing this component's source build.

## Install

Default — install everything **except monkey-sway** (which is opt-in via `--with-monkey-sway`). On **WSL or macOS** the default also drops monkey-hyprland — a Wayland desktop config is not applicable there (WSLg already renders single GUI apps; WSL has no VT login, so the guarded autostart block would stay inert). Pass `--with-monkey-hyprland` to install it anyway:

```bash
curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-env/master/install.sh | bash 2>&1 | tee monkey-env-install.log
```

> The one-liner needs `git` besides `curl` itself: the installer clones this repository into `~/Documents/monkey-env`, and every component installer it chains is fetched with `curl` and clones its own repo too — so `git` is required no matter how you run the installer. If `git` is missing, the script stops with an error — install it with your system's package manager and re-run the same command.

Vim-style selection — only the components you ask for (order is always normalized to the sequence above):

Installing both desktops appends two guarded autostart blocks to your shell rc — tail-class blocks keep the install order, so the first one in the file (monkey-hyprland's) wins: its `exec` replaces the login shell before sway's block is reached. This applies to whichever VT you log in on, not to tty1 specifically. Remove the other marker's lines to switch.

```bash
curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-env/master/install.sh | bash -s -- --with-monkey-tmux --with-monkey-zsh 2>&1 | tee monkey-env-install.log
```

Full install — every component, including the two opt-ins monkey-hyprland and monkey-sway, plus the kmscon console upgrade (`--with-kmscon`, default `tty2`; on WSL/macOS it is skipped with a warning). `2>&1 | tee` dumps the whole output (stdout and stderr) to `monkey-env-install.log` in the current directory while still printing it:

```bash
curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-env/master/install.sh | bash -s -- --with-kmscon --with-monkey-hyprland --with-monkey-sway --with-monkey-wezterm --with-monkey-tmux --with-monkey-zsh --with-monkey-nvim --with-monkey-vim --with-monkey-agent 2>&1 | tee monkey-env-install.log
```

From a local clone:

```bash
bash install.sh --with-monkey-wezterm
```

Optional console upgrade — `--with-kmscon [tty[,tty...]]` (default `tty2`) installs the kmscon package and enables `kmscon@ttyN` on the listed VTs while masking `getty@ttyN` there (above tty6 no default getty exists, so nothing is masked); the bare getty stays on every other VT as the last-resort console. Inside a kmscon session, the compositor autostart blocks wrap the compositor in `kmscon-launch-gui`, shipped by the distro kmscon packages; the session is recognised through `TERM=kmscon`, which only kmscon 10.0.0 and later sets. The flag is handled by this installer itself — it is **not** forwarded to the components — and is selected like any other `--with-*` entry: given alone, **only** the kmscon setup runs (a headless server with a GPU can pass `tty1`); combined with component flags it is additive and runs first in the chain. Pass `tty1` only when no display manager owns it — the runtime DM-collision check warns but does not stop. Setup failures never abort the install: unsupported environments (no systemd, no KMS/DRM, WSL, non-Linux) are skipped with a warning, and a skip counts as success — the run ends with `kmscon set up.` rather than listing it as failed.

```bash
bash install.sh --with-kmscon
bash install.sh --with-kmscon tty1,tty2
```

> **Why `bash -s --`?** `curl ... | bash --with-monkey-tmux` does not work: bash parses `--with-monkey-tmux` as its own option and exits with "invalid option". `-s` makes bash read the script from stdin, and `--` ends bash's option parsing — everything after it is forwarded to the script as positional parameters.

## `scripts/` (shared framework)

The `scripts/` directory is a [git subtree](https://git-scm.com/docs/git-subtree)
of [monkey-scripts](https://github.com/QMonkey/monkey-scripts) — the shared
install/checkhealth framework that this repo's `install.sh` is built on. Do
not edit it here; update it from upstream:

```bash
# first-time fetch (cloned without the subtree):
git subtree add -P scripts https://github.com/QMonkey/monkey-scripts.git master
# later updates:
git subtree pull -P scripts --squash https://github.com/QMonkey/monkey-scripts.git master
```

The one-click installer works without a subtree: on the `curl | bash` path it
clones _this_ repo straight into the install directory (`~/Documents/monkey-env`)
and runs the `install.sh` from that clone, so the installer and the `scripts/`
it loads always come from the same revision. If that directory already exists
but is not a git clone, the installer refuses to touch it and tells you so.
A regular `git clone` of this repo already contains `scripts/` —
there is nothing extra to clone or pull; framework updates land here through
the `git subtree pull` above and arrive in a clone through a plain
`git pull`. Only a checkout predating the subtree commit lacks `scripts/`:
`git pull` (or re-running `install.sh`, which pulls that checkout in place)
fixes it.

## What it does

1. Pre-authorize `sudo` once — the only password entry of the whole chain — and install a **temporary** NOPASSWD sudoers drop-in for the invoking user, removed automatically on exit. Without it, every component installer would ask for the password separately. If the drop-in cannot be installed, each component falls back to its own password handling
2. Run each selected component's installer in the fixed order above. Each installer is fetched in full before it is executed (`curl | bash` would run a truncated script if the connection dropped), retried, and falls back to a shallow `git clone` of the component repository when the raw.githubusercontent CDN is unreachable while the git endpoint still answers. Between components the chain re-exports the framework bin dirs and Homebrew, so a tool one component installed is found by the next instead of re-downloaded
3. Continue on failure — a broken component never blocks the rest; failed ones are listed at the end with per-component retry commands
4. Remove the NOPASSWD drop-in

All component installers are idempotent: re-runs update instead of reinstall, and running several `--with-*` combinations never duplicates work.

Exit status: 0 when every selected component succeeded, 1 when any of them failed — the summary lists the failures with per-component retry commands. A missing prerequisite aborts earlier with the same 1: an unsupported OS, or `git`/`curl` absent. An option this installer does not recognise is **not** an error — it prints the usage and exits 0 having installed nothing, so check the component list in the output, not just the exit code.

## Components

| Component                                                     | Provides                                                       |
| ------------------------------------------------------------- | -------------------------------------------------------------- |
| [monkey-hyprland](https://github.com/QMonkey/monkey-hyprland) | Hyprland desktop config (Lua `hl` API) + waybar                |
| [monkey-sway](https://github.com/QMonkey/monkey-sway)         | sway desktop config + waybar (opt-in via `--with-monkey-sway`) |
| [monkey-wezterm](https://github.com/QMonkey/monkey-wezterm)   | WezTerm terminal config (built from source)                    |
| [monkey-tmux](https://github.com/QMonkey/monkey-tmux)         | tmux config, TPM + plugins, fzf, auto-start on shell login     |
| [monkey-zsh](https://github.com/QMonkey/monkey-zsh)           | zsh config, zinit, fzf/zoxide/eza/go, login-shell switch       |
| [monkey-nvim](https://github.com/QMonkey/monkey-nvim)         | Neovim config (built from source) + LSP servers                |
| [monkey-vim](https://github.com/QMonkey/monkey-vim)           | Vim config (built from source) + LSP servers                   |
| [monkey-agent](https://github.com/QMonkey/monkey-agent)       | AI agent workstation: OpenCode, DSH, Qwen Code, OpenClaw       |

## Requirements

- One of the supported OS ids (Debian, Ubuntu, Arch, openSUSE, CentOS/RHEL/Rocky/AlmaLinux/Oracle Linux, Fedora) or macOS — derivatives are normalised to their parent id first (Linux Mint/Pop!_OS/elementary/Zorin → Ubuntu, Manjaro/EndeavourOS → Arch, openSUSE Leap/MicroOS/SLES → openSUSE). Anything outside that list is refused at the very start, before the first package question — there is no best-effort mode to fall through to
- `git` and `curl` on PATH — both are hard prerequisites of the chain (the installer checks them before it prints the component list, because every component is fetched with `curl` and clones its own repo with `git`)
- Network access to github.com and raw.githubusercontent.com (component installers are fetched at run time; the CDN has a `git clone` fallback)
- Overridable environment: `INSTALL_DIR` — where the bootstrap clone of this repo lands (default `~/Documents/monkey-env`); `SUDO_DROPIN=0` — skip the temporary NOPASSWD drop-in and ride the `sudo` timestamp instead, which costs one re-prompt when it expires mid-run; `SUDOERS_D_DIR` — where that drop-in is written (default `/etc/sudoers.d`)
