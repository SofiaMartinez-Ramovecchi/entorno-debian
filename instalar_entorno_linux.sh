#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Entorno de desarrollo para Debian
# Instala:
# - Zsh + Oh My Zsh (sin modificar ~/.zshrc)
# - Neovim estable en ~/.local (no en /tmp)
# - LazyVim
# - Git, curl, build tools
# - ripgrep, fd, fzf, bat, eza, zoxide, lazygit
# - Node.js mediante nvm + pnpm
# - Dagger CLI
# - Docker Engine
# ============================================================

log() { printf '\033[1;36m[INFO]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die() {
	printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2
	exit 1
}

trap 'die "Falló el instalador en la línea $LINENO."' ERR

if [[ "${EUID}" -eq 0 ]]; then
	die "Ejecutalo como usuario normal, no con sudo."
fi

if ! command -v sudo >/dev/null 2>&1; then
	die "No está instalado sudo."
fi

if [[ ! -r /etc/os-release ]]; then
	die "No se pudo detectar el sistema operativo."
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "debian" ]]; then
	die "Este instalador es únicamente para Debian. Sistema detectado: ${PRETTY_NAME:-desconocido}"
fi

export DEBIAN_FRONTEND=noninteractive
INSTALL_DIR="$HOME/.local"
BIN_DIR="$INSTALL_DIR/bin"
NVIM_DIR="$INSTALL_DIR/neovim"
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BIN_DIR"

log "Actualizando paquetes..."
sudo apt-get update
sudo apt-get upgrade -y
log "Instalando dependencias base..."
sudo apt-get install -y \
	build-essential \
	ca-certificates \
	curl \
	wget \
	git \
	unzip \
	zip \
	tar \
	gzip \
	xz-utils \
	jq \
	tree \
	make \
	gcc \
	g++ \
	pkg-config \
	python3 \
	python3-pip \
	python3-venv \
	python3-dev \
	pipx \
	zsh \
	tmux \
	ripgrep \
	fd-find \
	fzf \
	bat \
	shellcheck \
	xclip \
	wl-clipboard \
	openssh-client \
	gnupg \
	locales

# Debian instala fd y bat con estos nombres.
ln -sf "$(command -v fdfind)" "$BIN_DIR/fd" 2>/dev/null || true
ln -sf "$(command -v batcat)" "$BIN_DIR/bat" 2>/dev/null || true

# ------------------------------------------------------------
# PATH de esta ejecución
# ------------------------------------------------------------
# No se modifica ~/.zshrc ni ningún otro archivo de configuración de Zsh.
export PATH="$BIN_DIR:$PATH"

# ------------------------------------------------------------
# Neovim
# ------------------------------------------------------------
log "Instalando Neovim estable en $NVIM_DIR..."

ARCH="$(uname -m)"
case "$ARCH" in
x86_64 | amd64)
	NVIM_ARCHIVE="nvim-linux-x86_64.tar.gz"
	NVIM_FOLDER="nvim-linux-x86_64"
	;;
aarch64 | arm64)
	NVIM_ARCHIVE="nvim-linux-arm64.tar.gz"
	NVIM_FOLDER="nvim-linux-arm64"
	;;
*)
	die "Arquitectura no soportada automáticamente: $ARCH"
	;;
esac

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

curl -fL \
	"https://github.com/neovim/neovim/releases/latest/download/${NVIM_ARCHIVE}" \
	-o "$TMP_DIR/$NVIM_ARCHIVE"

tar -xzf "$TMP_DIR/$NVIM_ARCHIVE" -C "$TMP_DIR"
rm -rf "$NVIM_DIR"
mv "$TMP_DIR/$NVIM_FOLDER" "$NVIM_DIR"
ln -sfn "$NVIM_DIR/bin/nvim" "$BIN_DIR/nvim"

ok "Neovim instalado: $(nvim --version | head -n1)"

# ------------------------------------------------------------
# LazyVim
# ------------------------------------------------------------
log "Configurando LazyVim..."

for path in \
	"$HOME/.config/nvim" \
	"$HOME/.local/share/nvim" \
	"$HOME/.local/state/nvim" \
	"$HOME/.cache/nvim"; do
	if [[ -e "$path" ]]; then
		mv "$path" "${path}.bak-${BACKUP_SUFFIX}"
		warn "Backup creado: ${path}.bak-${BACKUP_SUFFIX}"
	fi
done

git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
rm -rf "$HOME/.config/nvim/.git"

# Ajustes personales básicos.
mkdir -p "$HOME/.config/nvim/lua/config"
cat >"$HOME/.config/nvim/lua/config/options.lua" <<'EOF'
vim.opt.clipboard = "unnamedplus"
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.mouse = "a"
vim.opt.wrap = false
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8
EOF

cat >"$HOME/.config/nvim/lua/config/keymaps.lua" <<'EOF'
local map = vim.keymap.set

map("n", "<C-s>", "<cmd>w<cr>", { desc = "Guardar archivo" })
map("i", "<C-s>", "<Esc><cmd>w<cr>a", { desc = "Guardar archivo" })
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Cerrar ventana" })
EOF

# Extras típicos para TypeScript, Docker, JSON, YAML, Java y Python.
mkdir -p "$HOME/.config/nvim/lua/plugins"
cat >"$HOME/.config/nvim/lua/plugins/extras.lua" <<'EOF'
return {
  { import = "lazyvim.plugins.extras.lang.typescript" },
  { import = "lazyvim.plugins.extras.lang.json" },
  { import = "lazyvim.plugins.extras.lang.yaml" },
  { import = "lazyvim.plugins.extras.lang.docker" },
  { import = "lazyvim.plugins.extras.lang.java" },
  { import = "lazyvim.plugins.extras.lang.python" },
  { import = "lazyvim.plugins.extras.formatting.prettier" },
  { import = "lazyvim.plugins.extras.linting.eslint" },
}
EOF

# ------------------------------------------------------------
# Oh My Zsh
# ------------------------------------------------------------
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
	log "Instalando Oh My Zsh..."
	RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
		sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

clone_or_update() {
	local repo="$1"
	local dir="$2"
	if [[ -d "$dir/.git" ]]; then
		git -C "$dir" pull --ff-only
	else
		git clone --depth=1 "$repo" "$dir"
	fi
}
clone_or_update \
	https://github.com/zsh-users/zsh-syntax-highlighting \
	"$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

# ------------------------------------------------------------
# Herramientas CLI modernas
# ------------------------------------------------------------
if ! command -v zoxide >/dev/null 2>&1; then
	log "Instalando zoxide..."
	curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
fi

if ! command -v eza >/dev/null 2>&1; then
	log "Instalando eza..."
	EZA_VERSION="$(curl -fsSL https://api.github.com/repos/eza-community/eza/releases/latest | jq -r .tag_name)"
	case "$ARCH" in
	x86_64 | amd64) EZA_TARGET="x86_64-unknown-linux-gnu" ;;
	aarch64 | arm64) EZA_TARGET="aarch64-unknown-linux-gnu" ;;
	esac
	curl -fL \
		"https://github.com/eza-community/eza/releases/download/${EZA_VERSION}/eza_${EZA_TARGET}.tar.gz" \
		-o "$TMP_DIR/eza.tar.gz"
	tar -xzf "$TMP_DIR/eza.tar.gz" -C "$TMP_DIR"
	install -m 0755 "$TMP_DIR/eza" "$BIN_DIR/eza"
fi

if ! command -v lazygit >/dev/null 2>&1; then
	log "Instalando lazygit..."
	LAZYGIT_VERSION="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r .tag_name | sed 's/^v//')"
	curl -fL \
		"https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_${ARCH/x86_64/x86_64}.tar.gz" \
		-o "$TMP_DIR/lazygit.tar.gz"
	tar -xzf "$TMP_DIR/lazygit.tar.gz" -C "$TMP_DIR" lazygit
	install -m 0755 "$TMP_DIR/lazygit" "$BIN_DIR/lazygit"
fi

# ------------------------------------------------------------
# Node.js + pnpm
# ------------------------------------------------------------
if [[ ! -d "$HOME/.nvm" ]]; then
	log "Instalando nvm..."
	export PROFILE=/dev/null
	curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
	unset PROFILE
fi

export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

log "Instalando Node.js LTS..."
nvm install --lts
nvm alias default 'lts/*'
nvm use default

corepack enable
corepack prepare pnpm@latest --activate

# ------------------------------------------------------------
# Dagger CLI
# ------------------------------------------------------------
if ! command -v dagger >/dev/null 2>&1; then
	log "Instalando Dagger CLI..."
	curl -fsSL https://dl.dagger.io/dagger/install.sh |
		DAGGER_INSTALL_TO="$BIN_DIR" sh
fi

# ------------------------------------------------------------
# GitHub CLI
# ------------------------------------------------------------
if ! command -v gh >/dev/null 2>&1; then
	log "Instalando GitHub CLI..."
	sudo mkdir -p -m 755 /etc/apt/keyrings
	curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg |
		sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
	sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" |
		sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
	sudo apt-get update
	sudo apt-get install -y gh
fi
# ------------------------------------------------------------
# Git + SSH para GitHub
# ------------------------------------------------------------
GIT_NAME="SofiaMartinez-Ramovecchi"
GIT_EMAIL="zunildaramivecchi@gmail.com"
SSH_KEY="$HOME/.ssh/id_ed25519"

log "Configurando Git..."

git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global push.autoSetupRemote true
git config --global commit.template "$HOME/.gitmessage"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [[ ! -f "$SSH_KEY" ]]; then
	log "Generando clave SSH para GitHub..."

	ssh-keygen \
		-t ed25519 \
		-C "$GIT_EMAIL" \
		-f "$SSH_KEY" \
		-N ""

	chmod 600 "$SSH_KEY"
	chmod 644 "$SSH_KEY.pub"
else
	warn "La clave SSH ya existe: $SSH_KEY"
fi

eval "$(ssh-agent -s)" >/dev/null
ssh-add "$SSH_KEY"

echo
ok "Clave pública SSH para pegar en GitHub:"
echo
cat "$SSH_KEY.pub"
echo

ok "Huella SHA256 de la clave:"
ssh-keygen -lf "$SSH_KEY.pub" -E sha256

echo
warn "Copiá la clave pública completa mostrada arriba."
warn "En GitHub: Settings → SSH and GPG keys → New SSH key."
warn "Después comprobá la conexión con: ssh -T git@github.com"
# ------------------------------------------------------------
# Docker Engine para Debian
# ------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
	log "Instalando Docker Engine..."
	curl -fsSL https://get.docker.com | sudo sh
	sudo usermod -aG docker "$USER"
	warn "Docker fue instalado. Cerrá sesión y volvé a entrar para usarlo sin sudo."
else
	ok "Docker ya está instalado."
fi

# ------------------------------------------------------------
# Shell predeterminada
# ------------------------------------------------------------
if [[ "$SHELL" != "$(command -v zsh)" ]]; then
	if chsh -s "$(command -v zsh)" "$USER" 2>/dev/null; then
		ok "Zsh quedó como shell predeterminada."
	else
		warn "No pude cambiar la shell automáticamente. Ejecutá: chsh -s $(command -v zsh)"
	fi
fi

# ------------------------------------------------------------
# Validación
# ------------------------------------------------------------
echo
ok "Instalación terminada."
echo
printf 'Neovim:  %s\n' "$(nvim --version | head -n1)"
printf 'Node:    %s\n' "$(node --version)"
printf 'pnpm:    %s\n' "$(pnpm --version)"
printf 'Dagger:  %s\n' "$(dagger version 2>/dev/null || true)"
printf 'GitHub:  %s\n' "$(gh --version | head -n1)"
printf 'Zsh:     %s\n' "$(zsh --version)"
echo
warn "Abrí una terminal nueva y ejecutá: nvim"
warn "La primera apertura de Neovim descargará los plugins de LazyVim."
