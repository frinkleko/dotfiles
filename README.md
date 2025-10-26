# Dotfiles

This repository manages my shell and tooling configuration and can optionally install a few common tools.

## Quick Start (zsh)
```zsh
git clone https://github.com/frinkleko/dotfiles.git && cd dotfiles && bash install.sh
```
Prefer step-by-step? Run each command individually inside zsh.

## Options
- `bash install.sh --no-packages`       # only link dotfiles
- `bash install.sh --no-zsh-default`    # keep your current default shell
- `bash install.sh --dry-run`           # preview actions without making changes
- `bash install.sh --install-clash`     # install clash-for-linux without prompting (defaults to gh-proxy.com)
- `bash install.sh --clash-use-proxy`   # force GitHub proxy for the clash installer
- `bash install.sh --clash-no-proxy`    # force direct GitHub access for the clash installer

## What Gets Installed (when packages are enabled)
- tmux
- htop
- zsh
- git
- uv *(best effort; falls back to the official installer if the package manager does not provide it)*
- clash-for-linux *(only when you accept the prompt or pass `--install-clash`; runs its upstream installer and launches `clashon` if available)*

## What Gets Linked
- `~/.tmux.conf`
- `~/.zshrc`
- `~/.config/htop/htoprc`

## Uninstall / Revert
- Remove the symlinks from `$HOME` and restore from the matching `~/.dotfiles_backup_*` directory if needed.
