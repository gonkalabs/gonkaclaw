# GonkaClaw

**Gonka.ai × OpenClaw** — one-command setup for almost-free AI agents.

GonkaClaw sets up [openGNK](https://github.com/gonkalabs/opengnk) (a Gonka inference proxy) and [OpenClaw](https://github.com/openclaw/openclaw) together, giving you a fully working AI agent framework powered by Gonka's decentralized inference network — at up to **100x less cost** than commercial APIs.

## Quick Start

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gonkalabs/gonkaclaw/main/setup.sh)
```

That's it. The script handles everything:

1. **Clones & builds openGNK** — fetches the repo and starts the Docker-based Gonka proxy
2. **Creates a Gonka wallet** — downloads the `inferenced` CLI, generates a keypair, registers on-chain
3. **Configures openGNK** — writes `.env` with wallet credentials, native tool calls enabled, multi-node retry
4. **Installs OpenClaw** — `npm install -g openclaw@latest`
5. **Configures OpenClaw** — sets openGNK (`localhost:8080/v1`) as the default AI provider with Qwen3 235B

## Prerequisites

| Requirement | Notes |
|---|---|
| **Docker** | Daemon must be running |
| **Node.js ≥ 22** | Required by OpenClaw |
| **git** | To clone openGNK |
| **curl** | To download inferenced |
| **unzip** | To extract inferenced |

## Configuration

All options are environment variables you can set before running the script:

| Variable | Default | Description |
|---|---|---|
| `INSTALL_DIR` | `./opengnk` | Where to clone the openGNK repo |
| `OPENGNK_PORT` | `8080` | Port for the openGNK proxy |
| `NODE_URL` | `http://node1.gonka.ai:8000` | Gonka genesis node for account creation |
| `ACCOUNT_NAME` | `opengnk-wallet` | Name for the local wallet keyring entry |

Example with custom port:

```bash
OPENGNK_PORT=9090 bash <(curl -fsSL https://raw.githubusercontent.com/gonkalabs/gonkaclaw/main/setup.sh)
```

## After Setup

1. **Fund your wallet** — go to [gonka.gg/faucet](https://gonka.gg/faucet) and paste your wallet address
2. **Open the dashboard** — run `openclaw dashboard`
3. **Try the proxy directly** —
   ```bash
   curl http://localhost:8080/v1/chat/completions \
     -H 'Content-Type: application/json' \
     -d '{"model":"Qwen/Qwen3-235B-A22B-Instruct-2507-FP8","messages":[{"role":"user","content":"Hello!"}]}'
   ```
4. **Open the web UI** — [http://localhost:8080](http://localhost:8080)

## What Gets Created

| Path | Description |
|---|---|
| `opengnk/` | Cloned openGNK repo with configured `.env` |
| `.data/` | `inferenced` binary + wallet keyring |
| `wallet-info.txt` | Wallet address, private key, mnemonic (chmod 600) |

## Why GonkaClaw?

Commercial AI APIs charge **$15–20 per million tokens**. Gonka's decentralized inference network provides the same models (Qwen3 235B with native tool calling, 240k context) at roughly **$0.15 per million tokens** — that's up to 100x cheaper.

GonkaClaw removes all the setup friction: no API keys to manage, no billing to configure, no vendor lock-in. Just run one command and start building.

## Links

- **GonkaClaw page** — [gonkalabs.com/gonkaclaw](https://gonkalabs.com/gonkaclaw/)
- **openGNK** — [github.com/gonkalabs/opengnk](https://github.com/gonkalabs/opengnk)
- **Gonka.ai** — [gonka.ai](https://gonka.ai)
- **Gonka Faucet** — [gonka.gg/faucet](https://gonka.gg/faucet)

## License

MIT
