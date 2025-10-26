#!/usr/bin/env bash
set -euo pipefail

# Config
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${HOME}"
SOURCE_DIR="${REPO_ROOT}/home"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="${HOME_DIR}/.dotfiles_backup_${TIMESTAMP}"
PACKAGE_MANAGER="none"

DO_PACKAGES=1
MAKE_ZSH_DEFAULT=0
DRY_RUN=0
INSTALL_CLASH=0
PROMPT_CLASH=1
CLASH_PROXY_MODE="proxy"
CLASH_CLONE_URL=""
CLASH_CLONE_NOTE=""
CLASH_REPO_DEFAULT_URL="https://github.com/nelvko/clash-for-linux-install.git"
CLASH_REPO_PROXY_URL="https://gh-proxy.com/https://github.com/nelvko/clash-for-linux-install.git"
CLASH_REPO_BRANCH="feat-init"

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]
  --no-packages         Do not install packages (only link dotfiles)
  --make-zsh-default    Change default shell to zsh (if available)
  --dry-run             Show what would be done, do not change anything
  --install-clash       Install clash-for-linux without prompting (defaults to proxy)
  --clash-use-proxy     Force GitHub proxy for clash-for-linux clone
  --clash-no-proxy      Force direct GitHub access for clash-for-linux clone
  -h, --help            Show this help
EOF
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-packages) DO_PACKAGES=0; shift ;;
    --make-zsh-default) MAKE_ZSH_DEFAULT=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
  --install-clash) INSTALL_CLASH=1; PROMPT_CLASH=0; shift ;;
    --clash-use-proxy) CLASH_PROXY_MODE="proxy"; shift ;;
    --clash-no-proxy) CLASH_PROXY_MODE="direct"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

ensure_in_repo_root() {
  if [[ ! -d "${SOURCE_DIR}" ]]; then
    echo "ERROR: Could not find '${SOURCE_DIR}'. Run this from the repo root."
    exit 1
  fi
}

detect_pkg_manager() {
  if have apt-get; then echo "apt"; return; fi
  if have dnf; then echo "dnf"; return; fi
  if have pacman; then echo "pacman"; return; fi
  if have zypper; then echo "zypper"; return; fi
  if have apk; then echo "apk"; return; fi
  if have brew; then echo "brew"; return; fi
  echo "none"
}

install_packages() {
  local pmgr="$1"
  local pkgs=(tmux htop zsh git)

  echo "Detected package manager: ${pmgr}"

  if [[ "${pmgr}" == "none" ]]; then
    echo "No supported package manager found. Skipping package installation."
    return 0
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[DRY RUN] Would install packages: ${pkgs[*]} using ${pmgr}"
    return 0
  fi

  case "${pmgr}" in
    apt)
      sudo apt-get update -y
      sudo apt-get install -y "${pkgs[@]}"
      ;;
    dnf)
      sudo dnf install -y "${pkgs[@]}"
      ;;
    pacman)
      sudo pacman -Sy --noconfirm --needed "${pkgs[@]}"
      ;;
    zypper)
      sudo zypper --non-interactive install -y "${pkgs[@]}" || sudo zypper install -y "${pkgs[@]}"
      ;;
    apk)
      sudo apk add --no-cache "${pkgs[@]}"
      ;;
    brew)
      brew update
      brew install "${pkgs[@]}" || true
      ;;
  esac
}

install_uv_with_package_manager() {
  local pmgr="$1"

  case "${pmgr}" in
    apt)
      if sudo apt-get install -y uv; then
        return 0
      fi
      ;;
    dnf)
      if sudo dnf install -y uv; then
        return 0
      fi
      ;;
    pacman)
      if sudo pacman -Sy --noconfirm --needed uv; then
        return 0
      fi
      ;;
    zypper)
      if sudo zypper --non-interactive install -y uv || sudo zypper install -y uv; then
        return 0
      fi
      ;;
    apk)
      if sudo apk add --no-cache uv; then
        return 0
      fi
      ;;
    brew)
      if brew install uv; then
        return 0
      fi
      ;;
  esac

  return 1
}

install_uv() {
  local pmgr="$1"

  if have uv; then
    echo "uv already installed."
    return 0
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    if [[ "${pmgr}" != "none" ]]; then
      echo "[DRY RUN] Would install uv via ${pmgr} (falls back to official installer if unavailable)."
    else
      echo "[DRY RUN] Would install uv via official installer script (requires curl)."
    fi
    return 0
  fi

  echo "Attempting to install uv"

  if [[ "${pmgr}" != "none" ]]; then
    if install_uv_with_package_manager "${pmgr}"; then
      echo "uv installation succeeded via ${pmgr}."
      return 0
    fi
    echo "uv package not available or failed via ${pmgr}."
  else
    echo "No supported package manager detected for uv."
  fi

  if have curl; then
    echo "Installing uv via official installer script."
    if curl -fsSL https://astral.sh/install.sh | sh; then
      echo "uv installed via official installer."
      return 0
    fi
    echo "Official uv installer failed."
  else
    echo "curl not available; cannot run official uv installer."
  fi

  echo "uv installation was not successful. Please install manually if needed."
  return 1
}

choose_clash_clone_url() {
  case "${CLASH_PROXY_MODE}" in
    proxy)
      CLASH_CLONE_URL="${CLASH_REPO_PROXY_URL}"
      CLASH_CLONE_NOTE="Using GitHub proxy for clash-for-linux (gh-proxy.com)."
      ;;
    direct)
      CLASH_CLONE_URL="${CLASH_REPO_DEFAULT_URL}"
      CLASH_CLONE_NOTE="Using direct GitHub access for clash-for-linux."
      ;;
    *)
      CLASH_CLONE_URL="${CLASH_REPO_PROXY_URL}"
      CLASH_CLONE_NOTE="Using GitHub proxy for clash-for-linux (default)."
      ;;
  esac
}

install_clash_for_linux() {
  if [[ "${INSTALL_CLASH}" -ne 1 ]]; then
    return
  fi

  if ! have git; then
    echo "git not available; cannot install clash-for-linux."
    return
  fi

  if ! have curl; then
    echo "Warning: curl not detected. clash-for-linux installer may require it; install curl if the installer fails."
  fi

  choose_clash_clone_url
  echo "${CLASH_CLONE_NOTE}"

  local clone_url="${CLASH_CLONE_URL}"
  local repo_dir
  local tmp_base
  tmp_base="${TMPDIR:-/tmp}"
  repo_dir="$(mktemp -d "${tmp_base%/}/clash-for-linux-XXXXXX" 2>/dev/null || mktemp -d -t clash-for-linux-XXXXXX)"

  if [[ -z "${repo_dir}" || ! -d "${repo_dir}" ]]; then
    echo "Failed to create temporary directory for clash-for-linux install."
    return 1
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[DRY RUN] Would clone ${clone_url} (branch ${CLASH_REPO_BRANCH}, depth 1) into ${repo_dir}/clash-for-linux-install"
    echo "[DRY RUN] Would run bash install.sh inside the cloned repository"
    rm -rf "${repo_dir}"
    return
  fi

  if ! git clone --branch "${CLASH_REPO_BRANCH}" --depth 1 "${clone_url}" "${repo_dir}/clash-for-linux-install"; then
    echo "Failed to clone clash-for-linux installer from ${clone_url}."
    rm -rf "${repo_dir}"
    return 1
  fi

  if ! (cd "${repo_dir}/clash-for-linux-install" && bash install.sh); then
    echo "clash-for-linux installer script failed. Check the log above."
    rm -rf "${repo_dir}"
    return 1
  fi

  rm -rf "${repo_dir}"
  echo "clash-for-linux installation script completed."

  if have clashon; then
    echo "Launching clashon..."
    if ! clashon; then
      echo "clashon exited with a non-zero status. Start it manually if needed."
    fi
  else
    echo "clashon command not found. Start it manually if desired."
  fi
}

maybe_prompt_for_clash_install() {
  if [[ "${PROMPT_CLASH}" -eq 0 ]]; then
    install_clash_for_linux
    return
  fi

  if [[ ! -t 0 || ! -t 1 ]]; then
    echo "Skipping clash-for-linux prompt (non-interactive session)."
    return
  fi

  echo
  local reply=""
  read -r -p "Install clash-for-linux using GitHub proxy (gh-proxy.com)? [y/N]: " reply || reply=""
  if [[ "${reply}" =~ ^[Yy] ]]; then
    INSTALL_CLASH=1
    CLASH_PROXY_MODE="proxy"
    install_clash_for_linux
  else
    echo "Skipping clash-for-linux install."
  fi
}

link_dotfiles() {
  echo "Linking dotfiles from ${SOURCE_DIR} to ${HOME_DIR}"
  local backed_up_any=0

  while IFS= read -r -d '' src; do
    local rel="${src#${SOURCE_DIR}/}"
    local dst="${HOME_DIR}/${rel}"
    local dst_dir
    dst_dir="$(dirname "${dst}")"

    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[DRY RUN] Would ensure dir: ${dst_dir}"
    else
      mkdir -p "${dst_dir}"
    fi

    if [[ -e "${dst}" && ! -L "${dst}" ]]; then
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "[DRY RUN] Would backup existing ${dst} to ${BACKUP_DIR}/${rel}"
      else
        mkdir -p "${BACKUP_DIR}/$(dirname "${rel}")"
        mv "${dst}" "${BACKUP_DIR}/${rel}"
        backed_up_any=1
      fi
    fi

    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[DRY RUN] Would link: ${dst} -> ${src}"
    else
      ln -sfn "${src}" "${dst}"
    fi
  done < <(find "${SOURCE_DIR}" -mindepth 1 \( -type f -o -type l \) -print0)

  if [[ "${backed_up_any}" -eq 1 && "${DRY_RUN}" -eq 0 ]]; then
    echo "Backups saved to: ${BACKUP_DIR}"
  fi
}

install_tmux_plugin_manager() {
  local tpm_dir="${HOME_DIR}/.tmux/plugins/tpm"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    if [[ -d "${tpm_dir}" ]]; then
      echo "[DRY RUN] Would update tmux plugin manager in ${tpm_dir}"
    else
      echo "[DRY RUN] Would clone tmux plugin manager into ${tpm_dir}"
    fi
    return
  fi

  if ! have git; then
    echo "git not available; skipping tmux plugin manager install."
    return
  fi

  if [[ -d "${tpm_dir}/.git" ]]; then
    echo "Updating tmux plugin manager in ${tpm_dir}"
    if ! (cd "${tpm_dir}" && git pull --ff-only); then
      echo "Failed to update tmux plugin manager; run 'git pull' in ${tpm_dir} manually."
    fi
    return
  fi

  if [[ -d "${tpm_dir}" ]]; then
    echo "tmux plugin manager directory exists but is not a git repo; skipping automatic install."
    return
  fi

  echo "Installing tmux plugin manager into ${tpm_dir}"
  mkdir -p "$(dirname "${tpm_dir}")"
  if ! git clone https://github.com/tmux-plugins/tpm "${tpm_dir}"; then
    echo "Failed to clone tmux plugin manager; install it manually if needed."
  fi
}

maybe_change_shell_to_zsh() {
  if [[ "${MAKE_ZSH_DEFAULT}" -ne 1 ]]; then
    echo "Skipping default shell change. Re-run with --make-zsh-default if desired."
    return
  fi

  if ! have zsh; then
    echo "zsh is not installed. Cannot change default shell."
    return
  fi

  local zsh_path
  zsh_path="$(command -v zsh)"

  if [[ "${SHELL:-}" == "${zsh_path}" ]]; then
    echo "zsh is already the default shell."
    return
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[DRY RUN] Would run: chsh -s ${zsh_path} \"${USER}\""
  else
    echo "Changing default shell to ${zsh_path} (you may need to log out/in)"
    chsh -s "${zsh_path}" "${USER}" || {
      echo "Failed to change default shell. You may need to add ${zsh_path} to /etc/shells or run with sudo."
    }
  fi
}

main() {
  ensure_in_repo_root
  PACKAGE_MANAGER="$(detect_pkg_manager)"

  maybe_prompt_for_clash_install

  if [[ "${DO_PACKAGES}" -eq 1 ]]; then
    install_packages "${PACKAGE_MANAGER}"
    install_uv "${PACKAGE_MANAGER}" || true
  else
    echo "Skipping package installation (--no-packages)"
  fi

  link_dotfiles
  install_tmux_plugin_manager
  maybe_change_shell_to_zsh
  echo "Done."
}

main "$@"
