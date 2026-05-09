#!/usr/bin/env bash
# ==============================================================================
# Christian Lempa's Dotfiles — Automated Installer
# Supports: Ubuntu/Debian (including WSL2) and macOS
# Source:   https://github.com/christianlempa/dotfiles
# ==============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m';  BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}${BOLD}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}${BOLD}[ERROR]${RESET} $*" >&2; }
step()    { echo -e "\n${BLUE}${BOLD}══ $* ══${RESET}"; }

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${BLUE}"
cat << 'EOF'
  ██████╗  ██████╗ ████████╗███████╗██╗██╗     ███████╗███████╗
  ██╔══██╗██╔═══██╗╚══██╔══╝██╔════╝██║██║     ██╔════╝██╔════╝
  ██║  ██║██║   ██║   ██║   █████╗  ██║██║     █████╗  ███████╗
  ██║  ██║██║   ██║   ██║   ██╔══╝  ██║██║     ██╔══╝  ╚════██║
  ██████╔╝╚██████╔╝   ██║   ██║     ██║███████╗███████╗███████║
  ╚═════╝  ╚═════╝    ╚═╝   ╚═╝     ╚═╝╚══════╝╚══════╝╚══════╝
  Christian Lempa's Dotfiles — Automated Installer
EOF
echo -e "${RESET}"

# ── Config ────────────────────────────────────────────────────────────────────
DOTFILES_REPO="https://github.com/christianlempa/dotfiles"
DOTFILES_DIR="$HOME/.dotfiles"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d_%H%M%S)"
NVM_VERSION="v0.40.1"
STARSHIP_VERSION="latest"

# ── OS Detection ──────────────────────────────────────────────────────────────
detect_os() {
    OS="unknown"
    IS_WSL=false
    IS_MACOS=false
    IS_LINUX=false

    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        IS_MACOS=true
    elif [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS="${ID}"
        IS_LINUX=true
        if grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then
            IS_WSL=true
        fi
    fi

    info "Detected OS: ${OS}$(${IS_WSL} && echo ' (WSL2)')"
}

# ── Dependency helpers ────────────────────────────────────────────────────────
cmd_exists() { command -v "$1" &>/dev/null; }

apt_install() {
    info "apt install: $*"
    sudo apt-get install -y --no-install-recommends "$@" 2>/dev/null
}

brew_install() {
    for pkg in "$@"; do
        if brew list --formula "$pkg" &>/dev/null 2>&1; then
            info "Homebrew (already installed): $pkg"
        else
            info "brew install: $pkg"
            brew install "$pkg"
        fi
    done
}

brew_cask_install() {
    for pkg in "$@"; do
        if brew list --cask "$pkg" &>/dev/null 2>&1; then
            info "Homebrew cask (already installed): $pkg"
        else
            info "brew install --cask: $pkg"
            brew install --cask "$pkg" || warn "Cask install failed (skipping): $pkg"
        fi
    done
}

# ── Backup existing dotfiles ──────────────────────────────────────────────────
backup_existing() {
    local files=( ".zshrc" ".zshenv" ".zsh" ".config/starship.toml"
                  ".config/ghostty" ".config/helix" ".config/neofetch"
                  ".config/yadm" ".hushlogin" ".warp" )
    local backed_up=false

    for f in "${files[@]}"; do
        local src="$HOME/$f"
        if [[ -e "$src" && ! -L "$src" ]]; then
            [[ "$backed_up" == "false" ]] && mkdir -p "$BACKUP_DIR" && backed_up=true
            local dest="$BACKUP_DIR/$(dirname "$f")"
            mkdir -p "$dest"
            cp -r "$src" "$dest/"
            info "Backed up: ~/$f → $BACKUP_DIR/$f"
        fi
    done

    [[ "$backed_up" == "true" ]] && success "Backups saved to: $BACKUP_DIR"
}

# ── Clone / update dotfiles repo ──────────────────────────────────────────────
fetch_dotfiles() {
    step "Fetching dotfiles"

    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        info "Dotfiles repo already exists — pulling latest..."
        git -C "$DOTFILES_DIR" pull --rebase --autostash
    else
        info "Cloning $DOTFILES_REPO → $DOTFILES_DIR"
        git clone --depth=1 "$DOTFILES_REPO" "$DOTFILES_DIR"
    fi
    success "Dotfiles repo ready at $DOTFILES_DIR"
}

# ── Linux: system prerequisites ───────────────────────────────────────────────
install_linux_prerequisites() {
    step "Installing Linux prerequisites"

    sudo apt-get update -qq
    apt_install \
        curl wget git unzip build-essential ca-certificates \
        software-properties-common apt-transport-https \
        gnupg lsb-release procps file pstree \
        zsh vim direnv jq

    success "Linux prerequisites installed"
}

# ── macOS: Xcode CLI tools ────────────────────────────────────────────────────
install_xcode_tools() {
    if ! xcode-select -p &>/dev/null; then
        step "Installing Xcode Command Line Tools"
        xcode-select --install
        info "Waiting for Xcode CLI tools installation to complete..."
        until xcode-select -p &>/dev/null; do sleep 5; done
        success "Xcode CLI tools installed"
    else
        info "Xcode CLI tools already installed"
    fi
}

# ── Homebrew ──────────────────────────────────────────────────────────────────
install_homebrew() {
    if cmd_exists brew; then
        info "Homebrew already installed"
    else
        step "Installing Homebrew"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Add brew to PATH for this session
        if $IS_MACOS; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        else
            eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        fi
    fi

    # Keep homebrew up-to-date
    brew update --quiet
    success "Homebrew ready"
}

# ── Zsh & plugins ─────────────────────────────────────────────────────────────
install_zsh() {
    step "Setting up Zsh"

    if ! cmd_exists zsh; then
        if $IS_MACOS; then brew_install zsh
        else apt_install zsh; fi
    else
        info "zsh already installed: $(zsh --version)"
    fi

    # Set zsh as default shell
    local zsh_path
    zsh_path="$(command -v zsh)"
    if [[ "$SHELL" != "$zsh_path" ]]; then
        if ! grep -qxF "$zsh_path" /etc/shells; then
            echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
        fi
        chsh -s "$zsh_path" "$USER"
        success "Default shell changed to zsh"
    else
        info "zsh is already the default shell"
    fi

    # Zsh plugins
    if $IS_MACOS; then
        brew_install zsh-autocomplete zsh-autosuggestions
    else
        # On Linux install via apt or compile from source
        local autocomplete_dir="/usr/local/share/zsh-autocomplete"
        local autosuggestions_dir="/usr/local/share/zsh-autosuggestions"

        if [[ ! -d "$autocomplete_dir" ]]; then
            info "Installing zsh-autocomplete..."
            sudo git clone --depth=1 \
                https://github.com/marlonrichert/zsh-autocomplete \
                "$autocomplete_dir"
        fi

        if [[ ! -d "$autosuggestions_dir" ]]; then
            info "Installing zsh-autosuggestions..."
            sudo git clone --depth=1 \
                https://github.com/zsh-users/zsh-autosuggestions \
                "$autosuggestions_dir"
        fi
    fi

    success "Zsh ready"
}

# ── Starship prompt ───────────────────────────────────────────────────────────
install_starship() {
    step "Installing Starship prompt"

    if cmd_exists starship; then
        info "Starship already installed: $(starship --version)"
    else
        if $IS_MACOS; then
            brew_install starship
        else
            curl -fsSL https://starship.rs/install.sh | sh -s -- --yes
        fi
    fi

    success "Starship installed"
}

# ── NVM (Node Version Manager) ────────────────────────────────────────────────
install_nvm() {
    step "Installing NVM"

    if [[ -d "$HOME/.nvm" ]]; then
        info "NVM already installed"
    else
        info "Installing NVM ${NVM_VERSION}..."
        curl -fsSL \
            "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
    fi

    success "NVM installed"
}

# ── Zoxide (smart cd) ─────────────────────────────────────────────────────────
install_zoxide() {
    step "Installing zoxide"

    if cmd_exists zoxide; then
        info "zoxide already installed"
    else
        if $IS_MACOS; then
            brew_install zoxide
        else
            curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
        fi
    fi

    success "zoxide installed"
}

# ── Direnv ────────────────────────────────────────────────────────────────────
install_direnv() {
    step "Installing direnv"

    if cmd_exists direnv; then
        info "direnv already installed"
    else
        if $IS_MACOS; then
            brew_install direnv
        else
            apt_install direnv
        fi
    fi

    success "direnv installed"
}

# ── Nerd Fonts (Hack Nerd Font) ───────────────────────────────────────────────
install_nerd_fonts() {
    step "Installing Hack Nerd Font"

    local font_dir
    if $IS_MACOS; then
        brew_cask_install font-hack-nerd-font
        return
    fi

    font_dir="$HOME/.local/share/fonts"
    mkdir -p "$font_dir"

    if ls "$font_dir"/Hack* &>/dev/null 2>&1; then
        info "Hack Nerd Font already installed"
        return
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    info "Downloading Hack Nerd Font..."
    curl -fsSL \
        "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.tar.xz" \
        -o "$tmp_dir/Hack.tar.xz"
    tar -xf "$tmp_dir/Hack.tar.xz" -C "$font_dir"
    rm -rf "$tmp_dir"
    fc-cache -fv "$font_dir" &>/dev/null
    success "Hack Nerd Font installed"
}

# ── macOS-specific tools (from yadm bootstrap) ────────────────────────────────
install_macos_tools() {
    step "Installing macOS formula tools"
    brew_install \
        ansible ansible-lint bat bottom cmatrix direnv \
        duf dust eza fzf gh glab helm httpie \
        hugo jq k3sup kubectx kubernetes-cli \
        nmap node opentofu packer python@3.13 \
        starship telnet terraform vhs wget \
        yamllint yq zoxide

    step "Installing macOS cask applications"
    brew_cask_install \
        1password-cli alt-tab discord github \
        google-chrome httpie notion notion-calendar \
        orbstack powershell raycast slack spotify \
        warp zoom

    success "macOS tools installed"
}

# ── Linux-specific tools (apt / cargo equivalents) ────────────────────────────
install_linux_tools() {
    step "Installing Linux CLI tools"

    # apt-available tools
    apt_install \
        bat curl fzf helm jq nmap wget \
        yamllint python3 python3-pip

    # eza (modern ls replacement)
    if ! cmd_exists eza; then
        info "Installing eza..."
        sudo mkdir -p /etc/apt/keyrings
        wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
            | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
        echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
            | sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null
        sudo apt-get update -qq
        apt_install eza
    fi

    # gh (GitHub CLI)
    if ! cmd_exists gh; then
        info "Installing GitHub CLI..."
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
https://cli.github.com/packages stable main" \
            | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
        sudo apt-get update -qq
        apt_install gh
    fi

    # kubectl
    if ! cmd_exists kubectl; then
        info "Installing kubectl..."
        curl -fsSL "https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key" \
            | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
        echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
            | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
        sudo apt-get update -qq
        apt_install kubectl
    fi

    # kubectx / kubens
    if ! cmd_exists kubectx; then
        info "Installing kubectx + kubens..."
        local kctx_tmp
        kctx_tmp="$(mktemp -d)"
        curl -fsSL https://github.com/ahmetb/kubectx/releases/latest/download/kubectx_linux_x86_64.tar.gz \
            | tar -xz -C "$kctx_tmp"
        sudo mv "$kctx_tmp/kubectx" /usr/local/bin/kubectx
        curl -fsSL https://github.com/ahmetb/kubectx/releases/latest/download/kubens_linux_x86_64.tar.gz \
            | tar -xz -C "$kctx_tmp"
        sudo mv "$kctx_tmp/kubens" /usr/local/bin/kubens
        rm -rf "$kctx_tmp"
    fi

    # Helm
    if ! cmd_exists helm; then
        info "Installing Helm..."
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi

    # Terraform
    if ! cmd_exists terraform; then
        info "Installing Terraform..."
        wget -qO- https://apt.releases.hashicorp.com/gpg \
            | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
            | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
        sudo apt-get update -qq
        apt_install terraform
    fi

    # Ansible
    if ! cmd_exists ansible; then
        info "Installing Ansible..."
        pip3 install --user ansible ansible-lint --break-system-packages 2>/dev/null \
            || pip3 install --user ansible ansible-lint
    fi

    # bottom (btm) — system monitor
    if ! cmd_exists btm; then
        info "Installing bottom (btm)..."
        local btm_deb
        btm_deb="$(curl -fsSL https://api.github.com/repos/ClementTsang/bottom/releases/latest \
            | jq -r '.assets[] | select(.name | test("bottom_.*.amd64.deb")) | .browser_download_url')"
        if [[ -n "$btm_deb" ]]; then
            local tmp_deb
            tmp_deb="$(mktemp --suffix=.deb)"
            curl -fsSL "$btm_deb" -o "$tmp_deb"
            sudo dpkg -i "$tmp_deb"
            rm -f "$tmp_deb"
        fi
    fi

    success "Linux tools installed"
}

# ── Copy dotfiles ─────────────────────────────────────────────────────────────
deploy_dotfiles() {
    step "Deploying dotfiles to HOME"

    # Create required directories
    mkdir -p \
        "$HOME/.zsh" \
        "$HOME/.config/ghostty/themes" \
        "$HOME/.config/helix/themes" \
        "$HOME/.config/neofetch" \
        "$HOME/.config/yadm" \
        "$HOME/.warp/themes" \
        "$HOME/.warp/workflows" \
        "$HOME/.local/bin"

    # ── Shell files ──────────────────────────────────────────────────────────
    cp "$DOTFILES_DIR/.zshrc"  "$HOME/.zshrc"
    cp "$DOTFILES_DIR/.zshenv" "$HOME/.zshenv"
    cp "$DOTFILES_DIR/.zsh/aliases.zsh"   "$HOME/.zsh/aliases.zsh"
    cp "$DOTFILES_DIR/.zsh/functions.zsh" "$HOME/.zsh/functions.zsh"
    cp "$DOTFILES_DIR/.zsh/nvm.zsh"       "$HOME/.zsh/nvm.zsh"
    cp "$DOTFILES_DIR/.zsh/starship.zsh"  "$HOME/.zsh/starship.zsh"
    cp "$DOTFILES_DIR/.zsh/wsl2fix.zsh"   "$HOME/.zsh/wsl2fix.zsh"
    cp "$DOTFILES_DIR/.hushlogin"         "$HOME/.hushlogin"

    # ── Starship prompt ───────────────────────────────────────────────────────
    cp "$DOTFILES_DIR/.config/starship.toml" "$HOME/.config/starship.toml"

    # ── Ghostty terminal ──────────────────────────────────────────────────────
    cp "$DOTFILES_DIR/.config/ghostty/config"                   "$HOME/.config/ghostty/config"
    cp "$DOTFILES_DIR/.config/ghostty/themes/xcad2k-dark"       "$HOME/.config/ghostty/themes/xcad2k-dark"
    cp "$DOTFILES_DIR/.config/ghostty/themes/xcad2k-light"      "$HOME/.config/ghostty/themes/xcad2k-light"

    # ── Helix editor ──────────────────────────────────────────────────────────
    cp "$DOTFILES_DIR/.config/helix/config.toml"                "$HOME/.config/helix/config.toml"
    cp "$DOTFILES_DIR/.config/helix/themes/christian.toml"      "$HOME/.config/helix/themes/christian.toml"

    # ── Neofetch ─────────────────────────────────────────────────────────────
    cp "$DOTFILES_DIR/.config/neofetch/config.conf"             "$HOME/.config/neofetch/config.conf"
    cp "$DOTFILES_DIR/.config/neofetch/thedigitallife.txt"      "$HOME/.config/neofetch/thedigitallife.txt"

    # ── Goto (directory bookmarks) ────────────────────────────────────────────
    cp "$DOTFILES_DIR/.config/goto"  "$HOME/.config/goto"

    # ── Warp terminal ─────────────────────────────────────────────────────────
    cp "$DOTFILES_DIR/.warp/keybindings.yaml"                   "$HOME/.warp/keybindings.yaml"
    cp "$DOTFILES_DIR/.warp/themes/xcad2k-dark.yml"             "$HOME/.warp/themes/xcad2k-dark.yml"
    cp "$DOTFILES_DIR/.warp/themes/xcad2k-light.yml"            "$HOME/.warp/themes/xcad2k-light.yml"
    cp "$DOTFILES_DIR/.warp/workflows/"*.yml                    "$HOME/.warp/workflows/" 2>/dev/null || true

    # ── yadm bootstrap ────────────────────────────────────────────────────────
    cp "$DOTFILES_DIR/.config/yadm/bootstrap"    "$HOME/.config/yadm/bootstrap"
    cp "$DOTFILES_DIR/.config/yadm/.gitignore"   "$HOME/.config/yadm/.gitignore"
    chmod +x "$HOME/.config/yadm/bootstrap"

    success "All dotfiles deployed to $HOME"
}

# ── Patch .zshrc for Linux ────────────────────────────────────────────────────
patch_zshrc_for_linux() {
    if $IS_MACOS; then return; fi

    step "Patching .zshrc for Linux"

    local zshrc="$HOME/.zshrc"

    # Replace HOMEBREW_PREFIX paths with Linux plugin paths
    sed -i \
        "s|source \$HOMEBREW_PREFIX/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh|[[ -f /usr/local/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh ]] \&\& source /usr/local/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh|g" \
        "$zshrc"

    sed -i \
        "s|source \$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh|[[ -f /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] \&\& source /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh|g" \
        "$zshrc"

    # Uncomment starship.zsh source (Christian commented it out on macOS)
    # but keep the direct eval as primary since it's already there

    # On WSL2: ensure wsl2fix is sourced
    if $IS_WSL; then
        if ! grep -q "wsl2fix" "$zshrc"; then
            echo "[[ -f ~/.zsh/wsl2fix.zsh ]] && source ~/.zsh/wsl2fix.zsh" >> "$zshrc"
        fi
    fi

    # Add zoxide init if not present
    if ! grep -q "zoxide init" "$zshrc"; then
        echo 'eval "$(zoxide init zsh)"' >> "$zshrc"
    fi

    # Add direnv hook if not present
    if ! grep -q "direnv hook" "$zshrc"; then
        echo 'eval "$(direnv hook zsh)"' >> "$zshrc"
    fi

    # Add starship init if not present
    if ! grep -q "starship init" "$zshrc"; then
        echo 'eval "$(starship init zsh)"' >> "$zshrc"
    fi

    # Strip macOS-only PATH entries that would cause errors on Linux
    sed -i \
        '/\/Users\/xcad\/.lmstudio/d;/opt\/homebrew\/opt\/libpq/d;/brew --prefix.*curl/d' \
        "$zshrc"

    success ".zshrc patched for Linux"
}

# ── Create secrets file stub ──────────────────────────────────────────────────
create_secrets_stub() {
    if [[ ! -f "$HOME/.zsh/secrets.zsh" ]]; then
        info "Creating secrets stub at ~/.zsh/secrets.zsh"
        cat > "$HOME/.zsh/secrets.zsh" << 'SECRETS'
# ~/.zsh/secrets.zsh — Store API keys, tokens, and private env vars here.
# This file is NOT tracked by git.
#
# Examples:
#   export GITHUB_TOKEN="ghp_..."
#   export OPENAI_API_KEY="sk-..."
#   export ANTHROPIC_API_KEY="sk-ant-..."
SECRETS
        chmod 600 "$HOME/.zsh/secrets.zsh"
        success "Created ~/.zsh/secrets.zsh (edit to add your secrets)"
    fi
}

# ── Post-install summary ──────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}${BOLD}║   ✅  Dotfiles installed successfully!               ║${RESET}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "${BOLD}What was installed:${RESET}"
    echo -e "  ${CYAN}•${RESET} Zsh + plugins (autocomplete, autosuggestions)"
    echo -e "  ${CYAN}•${RESET} Starship prompt with Christian's custom theme"
    echo -e "  ${CYAN}•${RESET} Ghostty, Helix, Neofetch, Warp configs"
    echo -e "  ${CYAN}•${RESET} NVM (Node Version Manager)"
    echo -e "  ${CYAN}•${RESET} zoxide (smart cd), direnv"
    echo -e "  ${CYAN}•${RESET} Hack Nerd Font"
    echo -e "  ${CYAN}•${RESET} CLI tools: eza, bat, fzf, gh, kubectl, helm, terraform..."
    echo -e "  ${CYAN}•${RESET} Aliases: k=kubectl, kc=kubectx, kn=kubens, tf=terraform..."
    echo ""
    echo -e "${BOLD}Next steps:${RESET}"
    echo -e "  1. ${YELLOW}Restart your terminal${RESET} (or run: exec zsh)"
    echo -e "  2. Add secrets to ${YELLOW}~/.zsh/secrets.zsh${RESET}"
    if $IS_LINUX; then
        echo -e "  3. Install a Nerd Font in your terminal emulator"
        echo -e "     to display icons correctly (Hack Nerd Font is installed)"
    fi
    echo ""
    if [[ -d "$BACKUP_DIR" ]]; then
        echo -e "  ${YELLOW}⚠${RESET}  Old configs backed up to: $BACKUP_DIR"
        echo ""
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    detect_os

    # Require git at minimum
    if ! cmd_exists git; then
        error "git is required. Please install git and re-run."
        exit 1
    fi

    backup_existing
    fetch_dotfiles

    if $IS_MACOS; then
        install_xcode_tools
        install_homebrew
        install_macos_tools   # installs everything from yadm bootstrap
    else
        install_linux_prerequisites
        install_homebrew      # optional but gets Linuxbrew; comment out if unwanted
        install_linux_tools
    fi

    install_zsh
    install_starship
    install_nvm
    install_zoxide
    install_direnv
    install_nerd_fonts
    deploy_dotfiles
    patch_zshrc_for_linux
    create_secrets_stub

    print_summary
}

main "$@"
