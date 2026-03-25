#!/usr/bin/env bash
set -euo pipefail

# ─── Colors & helpers ────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { printf "${BLUE}[info]${NC}  %s\n" "$*"; }
ok()    { printf "${GREEN}[  ok]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[warn]${NC}  %s\n" "$*"; }
err()   { printf "${RED}[ err]${NC}  %s\n" "$*" >&2; }
step()  { printf "\n${BOLD}${CYAN}── %s ──${NC}\n\n" "$*"; }

need() {
  if ! command -v "$1" &>/dev/null; then
    err "$1 is required but not installed."
    [ -n "${2:-}" ] && info "Install it: $2"
    exit 1
  fi
}

# ─── Pre-flight checks ──────────────────────────────────────────────────────

step "Pre-flight checks"

need docker "https://docs.docker.com/get-docker/"
need git    "https://git-scm.com"
need curl   ""
need unzip  ""

if ! docker info &>/dev/null; then
  err "Docker daemon is not running. Please start Docker and re-run this script."
  exit 1
fi
ok "Docker is running"

NODE_REQUIRED=22
if command -v node &>/dev/null; then
  NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
  if [ "$NODE_VERSION" -lt "$NODE_REQUIRED" ]; then
    err "Node.js >= $NODE_REQUIRED is required (found v$(node -v | sed 's/v//'))"
    info "Install via: https://nodejs.org or 'nvm install $NODE_REQUIRED'"
    exit 1
  fi
  ok "Node.js $(node -v) found"
else
  err "Node.js >= $NODE_REQUIRED is required for openCLAW."
  info "Install via: https://nodejs.org or 'nvm install $NODE_REQUIRED'"
  exit 1
fi

# ─── Configuration ───────────────────────────────────────────────────────────

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
if [[ "$SCRIPT_SOURCE" == /dev/fd/* ]] || [[ "$SCRIPT_SOURCE" == /proc/self/fd/* ]] || [ -z "$SCRIPT_SOURCE" ]; then
  SCRIPT_DIR="$(pwd)"
else
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
fi
INSTALL_DIR="${INSTALL_DIR:-$SCRIPT_DIR/opengnk}"
OPENGNK_PORT="${OPENGNK_PORT:-8080}"
NODE_URL="${NODE_URL:-http://node1.gonka.ai:8000}"
ACCOUNT_NAME="${ACCOUNT_NAME:-opengnk-wallet}"
DATA_DIR="$SCRIPT_DIR/.data"

# ─── Step 1: Clone & install openGNK ────────────────────────────────────────

step "Step 1/5 — Install openGNK"

if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
  ok "openGNK already cloned at $INSTALL_DIR"
  info "Pulling latest changes..."
  (cd "$INSTALL_DIR" && git pull --ff-only 2>/dev/null || true)
else
  info "Cloning openGNK..."
  git clone https://github.com/gonkalabs/opengnk.git "$INSTALL_DIR"
  ok "openGNK cloned to $INSTALL_DIR"
fi

# ─── Step 2: Create a new Gonka wallet ──────────────────────────────────────

step "Step 2/5 — Create a new Gonka wallet"

mkdir -p "$DATA_DIR"

INFERENCED_BIN="$DATA_DIR/inferenced"

if [ -f "$INFERENCED_BIN" ]; then
  ok "inferenced binary already present"
else
  info "Downloading inferenced CLI..."

  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    arm64)   ARCH="arm64" ;;
    *)       err "Unsupported architecture: $ARCH"; exit 1 ;;
  esac

  RELEASE_TAG="release/v0.2.10"
  case "$OS" in
    darwin) ZIP_NAME="inferenced-darwin-${ARCH}.zip" ;;
    linux)  ZIP_NAME="inferenced-linux-${ARCH}.zip" ;;
    *)      err "Unsupported OS: $OS"; exit 1 ;;
  esac

  DOWNLOAD_URL="https://github.com/gonka-ai/gonka/releases/download/${RELEASE_TAG}/${ZIP_NAME}"
  info "URL: $DOWNLOAD_URL"

  TMP_ZIP="$(mktemp)"
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_ZIP" "$TMP_DIR"' EXIT

  curl -fSL --progress-bar -o "$TMP_ZIP" "$DOWNLOAD_URL"
  unzip -qo "$TMP_ZIP" -d "$TMP_DIR"

  FOUND_BIN="$(find "$TMP_DIR" -name 'inferenced' -type f | head -1)"
  if [ -z "$FOUND_BIN" ]; then
    err "Could not find 'inferenced' binary in the downloaded archive."
    ls -la "$TMP_DIR"
    exit 1
  fi

  mv "$FOUND_BIN" "$INFERENCED_BIN"
  chmod +x "$INFERENCED_BIN"
  ok "inferenced downloaded"
fi

info "Creating Gonka wallet '${ACCOUNT_NAME}'..."
info "Node URL: $NODE_URL"

KEYRING_HOME="$DATA_DIR/keyring"
mkdir -p "$KEYRING_HOME"

WALLET_OUTPUT=$("$INFERENCED_BIN" keys add "$ACCOUNT_NAME" \
  --keyring-backend test \
  --home "$KEYRING_HOME" 2>&1) || {
    if echo "$WALLET_OUTPUT" | grep -qi "already exists\|overwrite"; then
      warn "Account '$ACCOUNT_NAME' already exists in keyring, reusing it."
    else
      err "Failed to create wallet keypair:"
      echo "$WALLET_OUTPUT"
      exit 1
    fi
  }

GONKA_ADDRESS=$(echo "$WALLET_OUTPUT" | grep -oE 'gonka1[a-z0-9]+' | head -1 || true)

if [ -z "$GONKA_ADDRESS" ]; then
  GONKA_ADDRESS=$("$INFERENCED_BIN" keys show "$ACCOUNT_NAME" \
    --keyring-backend test \
    --home "$KEYRING_HOME" -a 2>/dev/null || true)
fi

if [ -z "$GONKA_ADDRESS" ]; then
  err "Could not determine wallet address."
  echo "$WALLET_OUTPUT"
  exit 1
fi
ok "Wallet address: $GONKA_ADDRESS"

PUBKEY_BASE64=$("$INFERENCED_BIN" keys show "$ACCOUNT_NAME" \
  --keyring-backend test \
  --home "$KEYRING_HOME" \
  --output json 2>/dev/null \
  | python3 -c "import sys,json; d=json.load(sys.stdin); pk=json.loads(d['pubkey']); print(pk['key'])" 2>/dev/null || true)

if [ -n "$PUBKEY_BASE64" ]; then
  info "Registering wallet on-chain..."
  curl -sf -X POST "${NODE_URL}/v1/participants" \
    -H "Content-Type: application/json" \
    -d "{\"pub_key\":\"${PUBKEY_BASE64}\",\"address\":\"${GONKA_ADDRESS}\"}" &>/dev/null || true
  ok "Wallet registered with node"
else
  warn "Could not extract pubkey — skipping on-chain registration."
  warn "You may need to register manually with 'inferenced create-client'."
fi

MNEMONIC=$(echo "$WALLET_OUTPUT" | sed -n '/^[a-z].*[a-z]$/p' | tail -1 || true)
if [ -n "$MNEMONIC" ]; then
  info "Mnemonic phrase saved (see wallet-info.txt)"
fi

info "Exporting private key..."
GONKA_PRIVATE_KEY=$("$INFERENCED_BIN" keys export "$ACCOUNT_NAME" \
  --unarmored-hex --unsafe -y \
  --keyring-backend test \
  --home "$KEYRING_HOME" 2>&1 | grep -oE '[0-9a-fA-F]{64}' | head -1 || true)

if [ -z "$GONKA_PRIVATE_KEY" ]; then
  err "Could not export private key."
  exit 1
fi
ok "Private key exported (${#GONKA_PRIVATE_KEY} hex chars)"

# ─── Step 3: Configure and start openGNK ────────────────────────────────────

step "Step 3/5 — Configure & start openGNK"

ENV_FILE="$INSTALL_DIR/.env"

cat > "$ENV_FILE" <<EOF
GONKA_PRIVATE_KEY=${GONKA_PRIVATE_KEY}
GONKA_ADDRESS=${GONKA_ADDRESS}
GONKA_SOURCE_URL=${NODE_URL}
SIMULATE_TOOL_CALLS=false
NATIVE_TOOL_CALLS=true
SANITIZE=false
GONKA_RETRY_STRATEGY=other_nodes
GONKA_MAX_RETRIES=8
PORT=${OPENGNK_PORT}
EOF

ok "Wrote $ENV_FILE"

info "Building and starting openGNK..."
(cd "$INSTALL_DIR" && docker compose up -d --build)

info "Waiting for openGNK to become healthy..."
RETRIES=0
MAX_RETRIES=60
until curl -sf "http://localhost:${OPENGNK_PORT}/health" &>/dev/null; do
  RETRIES=$((RETRIES + 1))
  if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
    err "openGNK did not become healthy after ${MAX_RETRIES}s"
    info "Check logs with: cd $INSTALL_DIR && make logs"
    exit 1
  fi
  sleep 1
done
ok "openGNK is running at http://localhost:${OPENGNK_PORT}"

# ─── Step 4: Install openCLAW ───────────────────────────────────────────────

step "Step 4/5 — Install openCLAW"

if command -v openclaw &>/dev/null; then
  ok "openCLAW is already installed ($(openclaw --version 2>/dev/null || echo 'unknown version'))"
else
  info "Installing openCLAW via npm..."
  npm install -g openclaw@latest
  ok "openCLAW installed"
fi

# ─── Step 5: Configure openCLAW with openGNK ────────────────────────────────

step "Step 5/5 — Configure openCLAW with openGNK as default provider"

OPENGNK_BASE_URL="http://localhost:${OPENGNK_PORT}/v1"

info "Running openclaw onboard (non-interactive)..."
info "Base URL: $OPENGNK_BASE_URL"
info "Model:    Qwen/Qwen3-235B-A22B-Instruct-2507-FP8"

openclaw onboard --non-interactive \
  --mode local \
  --auth-choice custom-api-key \
  --custom-base-url "$OPENGNK_BASE_URL" \
  --custom-model-id "Qwen/Qwen3-235B-A22B-Instruct-2507-FP8" \
  --custom-api-key "not-needed" \
  --custom-compatibility openai \
  --install-daemon \
  --accept-risk \
  --skip-skills \
  --skip-channels \
  --skip-health

# openCLAW defaults to conservative 16k context / 4k output — patch to real limits
OPENCLAW_CFG="$HOME/.openclaw/openclaw.json"
if [ -f "$OPENCLAW_CFG" ] && command -v python3 &>/dev/null; then
  python3 -c "
import json, sys
with open('$OPENCLAW_CFG') as f:
    cfg = json.load(f)
for prov in cfg.get('models', {}).get('providers', {}).values():
    for m in prov.get('models', []):
        m['contextWindow'] = 240000
        m['maxTokens'] = 10000
with open('$OPENCLAW_CFG', 'w') as f:
    json.dump(cfg, f, indent=2)
" && ok "Patched model limits: 240k context, 10k max output tokens"
fi

ok "openCLAW configured with openGNK"

# ─── Done ────────────────────────────────────────────────────────────────────

step "Setup complete!"

printf "${GREEN}${BOLD}"
cat <<'BANNER'
   ___                   ____ _   _ _  __
  / _ \ _ __   ___ _ __ / ___| \ | | |/ /
 | | | | '_ \ / _ \ '_ \ |  _|  \| | ' / 
 | |_| | |_) |  __/ | | | |_| | |\  | . \ 
  \___/| .__/ \___|_| |_|\____|_| \_|_|\_\
       |_|        + openCLAW
BANNER
printf "${NC}\n"

echo ""
printf "${BOLD}Your Gonka wallet address:${NC}\n"
printf "\n  ${CYAN}${BOLD}%s${NC}\n\n" "$GONKA_ADDRESS"

printf "${BOLD}Services running:${NC}\n"
printf "  • openGNK proxy:  ${CYAN}http://localhost:${OPENGNK_PORT}${NC}\n"
printf "  • openGNK Web UI: ${CYAN}http://localhost:${OPENGNK_PORT}${NC}\n"
printf "  • openCLAW:       ${CYAN}openclaw dashboard${NC}\n"
echo ""

printf "${YELLOW}${BOLD}⚡ Next step — fund your wallet:${NC}\n"
echo ""
printf "  1. Go to ${CYAN}${BOLD}https://gonka.gg/faucet${NC}\n"
printf "  2. Paste your address: ${CYAN}%s${NC}\n" "$GONKA_ADDRESS"
printf "  3. Claim free GNK tokens (0.01 GNK per 24h)\n"
echo ""
printf "${DIM}You need GNK tokens to pay for inference on the Gonka network.${NC}\n"
printf "${DIM}Once funded, try: curl http://localhost:${OPENGNK_PORT}/v1/chat/completions -H 'Content-Type: application/json' -d '{\"model\":\"Qwen/Qwen3-235B-A22B-Instruct-2507-FP8\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello!\"}]}'${NC}\n"
echo ""

WALLET_INFO="$SCRIPT_DIR/wallet-info.txt"
cat > "$WALLET_INFO" <<EOF
# Gonka Wallet Info — $(date)
# KEEP THIS FILE SECURE — it contains your private key and mnemonic!

GONKA_ADDRESS=${GONKA_ADDRESS}
GONKA_PRIVATE_KEY=${GONKA_PRIVATE_KEY}
NODE_URL=${NODE_URL}
OPENGNK_URL=http://localhost:${OPENGNK_PORT}
EOF

if [ -n "${MNEMONIC:-}" ]; then
  cat >> "$WALLET_INFO" <<EOF

# Mnemonic (recovery phrase) — store securely!
MNEMONIC=${MNEMONIC}
EOF
fi

cat >> "$WALLET_INFO" <<EOF

# Fund your wallet at: https://gonka.gg/faucet
EOF
chmod 600 "$WALLET_INFO"
info "Wallet details saved to $WALLET_INFO (chmod 600)"
