#!/usr/bin/env bash
#
# Script Name: git-setup
# Description: git セットアップスクリプト
# Usage: bash <(curl -sL https://raw.githubusercontent.com/opipi406/linux-setup-tools/main/git-setup/install.sh)
#
# Requirements: Bash 4.0+, curl

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_NAME="git-setup"

GIT_COMPLETION_URL="https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash"
GIT_PROMPT_URL="https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh"
GIT_COMPLETION_PATH="$HOME/.git-completion.bash"
GIT_PROMPT_PATH="$HOME/.git-prompt.sh"
BASHRC_PATH="$HOME/.bashrc"

REPO_BASE_URL="https://raw.githubusercontent.com/opipi406/linux-setup-tools/main/git-prompt"

# =============================================================================
# Color and Icon Definitions
# =============================================================================

if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    COLOR_ENABLED=true
else
    COLOR_ENABLED=false
fi

if $COLOR_ENABLED; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' BOLD='' DIM='' NC=''
fi

ICON_CHECK="✓"
ICON_CROSS="✗"
ICON_WARN="⚠"
ICON_INFO="ℹ"
ICON_ARROW="→"
ICON_BULLET="•"

# =============================================================================
# Output Functions
# =============================================================================

info() {
    printf "${BLUE}${ICON_INFO}  %s${NC}\n" "$*"
}

success() {
    printf "${GREEN}${ICON_CHECK}  %s${NC}\n" "$*"
}

warn() {
    printf "${YELLOW}${ICON_WARN}  %s${NC}\n" "$*" >&2
}

error() {
    printf "${RED}${ICON_CROSS}  %s${NC}\n" "$*" >&2
}

step() {
    local current="$1"
    local total="$2"
    local message="$3"
    printf "${CYAN}[%d/%d]${NC} %s\n" "$current" "$total" "$message"
}

header() {
    local text="$1"
    local width=${2:-60}
    printf "\n${BOLD}%s${NC}\n" "$text"
    printf "${DIM}%s${NC}\n" "$(printf '─%.0s' $(seq 1 "$width"))"
}

# =============================================================================
# Interactive Functions
# =============================================================================

confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-n}"
    local reply

    if [[ "$default" =~ ^[Yy] ]]; then
        prompt="$prompt [Y/n] "
    else
        prompt="$prompt [y/N] "
    fi

    printf "${MAGENTA}${prompt}${NC}"
    read -r reply

    if [[ -z "$reply" ]]; then
        reply="$default"
    fi

    [[ "$reply" =~ ^[Yy] ]]
}

# =============================================================================
# Spinner Functions
# =============================================================================

spinner() {
    local message="$1"
    shift
    local pid
    local spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    "$@" &
    pid=$!

    printf '\033[?25l'

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${CYAN}[%s]${NC} %s" "${spin_chars:i++%${#spin_chars}:1}" "$message"
        sleep 0.1
    done

    wait "$pid"
    local exit_code=$?

    printf '\033[?25h'
    printf '\r\033[K'

    if [[ $exit_code -eq 0 ]]; then
        success "$message"
    else
        error "$message"
    fi

    return $exit_code
}

# =============================================================================
# Utility Functions
# =============================================================================

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        error "必要なコマンドが見つかりません: $cmd"
        exit 1
    fi
}

cleanup() {
    :
}

# =============================================================================
# Signal Handling
# =============================================================================

trap cleanup EXIT
trap 'echo; error "中断されました"; exit 130' INT
trap 'error "終了シグナルを受信しました"; exit 143' TERM

# =============================================================================
# Usage and Help
# =============================================================================

usage() {
    printf '%b\n' "
${BOLD}Usage:${NC} install.sh [options]

${BOLD}Description:${NC}
    git-completion.bash / git-prompt.sh セットアップスクリプト
    GitHubリポジトリからファイルをダウンロードし、.bashrc に設定を追加します。

${BOLD}Options:${NC}
    -h, --help      ヘルプを表示
    -f, --force     確認なしで実行

${BOLD}Remote Usage:${NC}
    bash <(curl -sL ${REPO_BASE_URL}/install.sh)

${BOLD}Examples:${NC}
    install.sh
    install.sh --force
"
}

# =============================================================================
# Argument Parsing
# =============================================================================

FORCE=false

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -h | --help)
            usage
            exit 0
            ;;
        -f | --force)
            FORCE=true
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            error "不明なオプション: $1"
            usage >&2
            exit 2
            ;;
        *)
            break
            ;;
        esac
    done
}

# =============================================================================
# Core Functions
# =============================================================================

download_git_completion() {
    curl -fsSL "$GIT_COMPLETION_URL" -o "$GIT_COMPLETION_PATH"
    chmod +x "$GIT_COMPLETION_PATH"
}

download_git_prompt() {
    curl -fsSL "$GIT_PROMPT_URL" -o "$GIT_PROMPT_PATH"
    chmod +x "$GIT_PROMPT_PATH"
}

backup_git_files() {
    local backup_dir="$HOME/.git-prompt-backup.$(date +%Y%m%d%H%M%S)"
    mkdir -p "$backup_dir"

    if [[ -f "$GIT_COMPLETION_PATH" ]]; then
        cp "$GIT_COMPLETION_PATH" "$backup_dir/"
    fi
    if [[ -f "$GIT_PROMPT_PATH" ]]; then
        cp "$GIT_PROMPT_PATH" "$backup_dir/"
    fi

    echo "$backup_dir"
}

check_bashrc_configured() {
    if [[ ! -f "$BASHRC_PATH" ]]; then
        return 1
    fi
    grep -q '\.git-completion\.bash\|\.git-prompt\.sh\|__git_ps1' "$BASHRC_PATH" 2>/dev/null
}

add_bashrc_config() {
    local config
    config=$(
        cat <<'BASHRC_EOF'

# Git prompt configuration (added by git-prompt-setup)
if [ -f "$HOME/.git-completion.bash" ]; then
    source "$HOME/.git-completion.bash"
fi
if [ -f "$HOME/.git-prompt.sh" ]; then
    source "$HOME/.git-prompt.sh"
    GIT_PS1_SHOWDIRTYSTATE=true
    export PS1='[\u@\h \[\033[01;33m\]\w\[\033[01;31m\]$(__git_ps1 " (%s)")\[\e[m\]]\$ '
fi
BASHRC_EOF
    )
    if [[ ! -f "$BASHRC_PATH" ]]; then
        printf "%s\n" "$config" >"$BASHRC_PATH"
    else
        printf "%s\n" "$config" >>"$BASHRC_PATH"
    fi
}

print_manual_config() {
    printf "\n${DIM}手動で .bashrc に以下を追加してください:${NC}\n"
    cat <<'MANUAL_EOF'

  # Git prompt configuration
  if [ -f "$HOME/.git-completion.bash" ]; then
      source "$HOME/.git-completion.bash"
  fi
  if [ -f "$HOME/.git-prompt.sh" ]; then
      source "$HOME/.git-prompt.sh"
      GIT_PS1_SHOWDIRTYSTATE=true
      export PS1='\h \[\033[01;33m\]\w\[\033[01;31m\]$(__git_ps1 " (%s)")\[\e[m\] \$ '
  fi

MANUAL_EOF
}

# =============================================================================
# Main Logic
# =============================================================================

parse_args "$@"

header "Git Prompt Setup"

TOTAL_STEPS=4

# Step 1: 環境チェック
step 1 $TOTAL_STEPS "環境をチェックしています..."
require_command curl

if [[ ! -d "$HOME" ]] || [[ ! -w "$HOME" ]]; then
    error "HOMEディレクトリに書き込み権限がありません: $HOME"
    exit 1
fi
success "環境チェック完了"

# Step 2: 既存ファイルの確認
step 2 $TOTAL_STEPS "既存ファイルを確認しています..."

EXISTING_FILES=false
if [[ -f "$GIT_COMPLETION_PATH" ]] || [[ -f "$GIT_PROMPT_PATH" ]]; then
    EXISTING_FILES=true
    [[ -f "$GIT_COMPLETION_PATH" ]] && warn "既存ファイルを検出: $GIT_COMPLETION_PATH"
    [[ -f "$GIT_PROMPT_PATH" ]] && warn "既存ファイルを検出: $GIT_PROMPT_PATH"

    if $FORCE; then
        backup_dir=$(backup_git_files)
        info "バックアップを作成しました ${ICON_ARROW} $backup_dir"
    else
        if confirm "既存ファイルをバックアップして上書きしますか？"; then
            backup_dir=$(backup_git_files)
            info "バックアップを作成しました ${ICON_ARROW} $backup_dir"
        else
            info "セットアップを中止しました"
            exit 0
        fi
    fi
else
    info "既存ファイルはありません。新規ダウンロードします"
fi

# Step 3: ダウンロード
step 3 $TOTAL_STEPS "ファイルをダウンロードしています..."
spinner "git-completion.bash をダウンロード中" download_git_completion
spinner "git-prompt.sh をダウンロード中" download_git_prompt
info "配置先: $GIT_COMPLETION_PATH"
info "配置先: $GIT_PROMPT_PATH"

# Step 4: .bashrc の設定
step 4 $TOTAL_STEPS ".bashrc の設定を確認しています..."

if check_bashrc_configured; then
    success ".bashrc に git-prompt の設定が既に存在します"
else
    if $FORCE; then
        add_bashrc_config
        success ".bashrc に git-prompt の設定を追加しました"
    else
        if [[ ! -f "$BASHRC_PATH" ]]; then
            if confirm ".bashrc が存在しません。新規作成して設定を追加しますか？" "y"; then
                add_bashrc_config
                success ".bashrc を新規作成し、git-prompt の設定を追加しました"
            else
                warn ".bashrc への設定追加をスキップしました"
                print_manual_config
            fi
        else
            if confirm ".bashrc に git-prompt の設定を追加しますか？" "y"; then
                add_bashrc_config
                success ".bashrc に git-prompt の設定を追加しました"
            else
                warn ".bashrc への設定追加をスキップしました"
                print_manual_config
            fi
        fi
    fi
fi

echo
success "git-prompt のセットアップが完了しました"
info "設定を反映するには: source ~/.bashrc"
echo
