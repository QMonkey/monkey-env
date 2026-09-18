# monkey-env

One-shot meta-installer for the monkey-* family. Chains the component installers in dependency order with a single password entry:

```text
monkey-zsh -> monkey-hyprland -> monkey-sway -> monkey-wezterm -> monkey-tmux -> monkey-nvim -> monkey-vim
```

monkey-zsh runs first on purpose: it switches the login shell to zsh before anything else, so the env blocks the later components persist land in `~/.zprofile` (which zsh reads) instead of `.profile`.

## Install

Default — install everything **except monkey-sway** (which is opt-in via `--with-monkey-sway`). On **WSL or macOS** the default also drops monkey-hyprland — a Wayland desktop config is not applicable there (WSLg already renders single GUI apps; WSL has no VT login, so the guarded autostart block would stay inert). Pass `--with-monkey-hyprland` to install it anyway:

```bash
curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-env/main/install.sh | bash
```

Vim-style selection — only the components you ask for (order is always normalized to the sequence above):

Installing both desktops appends two guarded autostart blocks to your shell rc — the first one in the file (monkey-hyprland's) wins on tty1; remove the other marker's lines to switch.

```bash
curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-env/main/install.sh | bash -s -- --with-monkey-tmux --with-monkey-zsh
```

From a local clone:

```bash
bash install.sh --with-monkey-wezterm
```

> **Why `bash -s --`?** `curl ... | bash --with-monkey-tmux` does not work: bash parses `--with-monkey-tmux` as its own option and exits with "invalid option". `-s` makes bash read the script from stdin, and `--` ends bash's option parsing — everything after it is forwarded to the script as positional parameters.

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

- One of the supported Linux distros (Debian/Ubuntu, Arch, openSUSE, CentOS/RHEL/Fedora family) or macOS
- Network access to github.com (component installers are fetched at run time)
