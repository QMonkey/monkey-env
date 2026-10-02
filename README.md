# monkey-env

One-shot meta-installer for the monkey-* family. Chains the component installers in dependency order with a single password entry:

```text
monkey-zsh -> monkey-wezterm -> monkey-hyprland -> monkey-sway -> monkey-tmux -> monkey-nvim -> monkey-vim
```

monkey-zsh runs first on purpose: it switches the login shell to zsh before anything else, so the env blocks the later components persist land in `~/.zprofile` (which zsh reads) instead of `.profile`.

monkey-wezterm runs before the compositors on purpose: both monkey-hyprland and monkey-sway treat WezTerm as their default terminal and would otherwise try to install it themselves, bypassing this component's source build.

## Install

Default — install everything **except monkey-sway** (which is opt-in via `--with-monkey-sway`). On **WSL or macOS** the default also drops monkey-hyprland — a Wayland desktop config is not applicable there (WSLg already renders single GUI apps; WSL has no VT login, so the guarded autostart block would stay inert). Pass `--with-monkey-hyprland` to install it anyway:

```bash
curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-env/master/install.sh | bash
```

> The one-liner needs `git` besides `curl` itself: the installer clones this repository into `~/Documents/monkey-env`, and every component installer it chains is fetched with `curl` and clones its own repo too — so `git` is required no matter how you run the installer. If `git` is missing, the script stops with an error — install it with your system's package manager and re-run the same command.

Vim-style selection — only the components you ask for (order is always normalized to the sequence above):

Installing both desktops appends two guarded autostart blocks to your shell rc — the first one in the file (monkey-hyprland's) wins on tty1; remove the other marker's lines to switch.

```bash
curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-env/master/install.sh | bash -s -- --with-monkey-tmux --with-monkey-zsh
```

Full install — every component, including the two opt-ins monkey-hyprland and monkey-sway, plus the kmscon console upgrade (`--with-kmscon`, default `tty2`; on WSL/macOS it is skipped with a warning). `2>&1 | tee` dumps the whole output (stdout and stderr) to `monkey-env-install.log` in the current directory while still printing it:

```bash
curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-env/master/install.sh | bash -s -- --with-kmscon --with-monkey-hyprland --with-monkey-sway --with-monkey-wezterm --with-monkey-tmux --with-monkey-zsh --with-monkey-nvim --with-monkey-vim 2>&1 | tee monkey-env-install.log
```

From a local clone:

```bash
bash install.sh --with-monkey-wezterm
```

Optional console upgrade — `--with-kmscon [tty[,tty...]]` (default `tty2`) installs the kmscon package and enables `kmscon@ttyN` on the listed VTs while masking `getty@ttyN` there; the bare getty stays on every other VT as the last-resort console. Inside a kmscon session, the compositor autostart blocks wrap the compositor in `kmscon-launch-gui`, shipped by the distro kmscon packages. The flag is handled by this installer itself — it is **not** forwarded to the components — and is selected like any other `--with-*` entry: given alone, **only** the kmscon setup runs (a headless server with a GPU can pass `tty1`); combined with component flags it is additive and runs first in the chain. Pass `tty1` only when no display manager owns it — the runtime DM-collision check warns but does not stop. Setup failures never abort the install: unsupported environments (no systemd/KMS) are skipped with a warning.

```bash
bash install.sh --with-kmscon
bash install.sh --with-kmscon tty1,tty2
```

> **Why `bash -s --`?** `curl ... | bash --with-monkey-tmux` does not work: bash parses `--with-monkey-tmux` as its own option and exits with "invalid option". `-s` makes bash read the script from stdin, and `--` ends bash's option parsing — everything after it is forwarded to the script as positional parameters.

## `scripts/` (shared framework)

The `scripts/` directory is a [git subtree](https://git-scm.com/docs/git-subtree)
of [monkey-scripts](https://github.com/QMonkey/monkey-scripts) — the shared
install/checkhealth framework that this repo's `install.sh` and
`checkhealth.sh` are built on. Do not edit it here; update it from upstream:

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
Once the subtree above is committed and
pushed, a regular `git clone` of this repo already contains `scripts/` —
there is nothing extra to clone or pull; updates arrive through a plain
`git pull`. Only a checkout from before that commit lacks `scripts/`:
`git pull` (or re-running `install.sh`, which pulls that checkout in place)
fixes it.

## What it does

1. Pre-authorize `sudo` once — the only password entry of the whole chain — and install a **temporary** NOPASSWD sudoers drop-in for the invoking user, removed automatically on exit. Without it, every component installer would ask for the password separately (five prompts). If the drop-in cannot be installed, each component falls back to its own password handling
2. Run each selected component's installer (fetched from the component repo at run time) in the fixed order above
3. Continue on failure — a broken component never blocks the rest; failed ones are listed at the end with per-component retry commands
4. Remove the NOPASSWD drop-in

All component installers are idempotent: re-runs update instead of reinstall, and running several `--with-*` combinations never duplicates work.

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

## Requirements

- One of the supported Linux distros (Debian, Ubuntu, Arch, openSUSE, CentOS/RHEL/Rocky/Alma, Fedora) or macOS
- Network access to github.com (component installers are fetched at run time)
