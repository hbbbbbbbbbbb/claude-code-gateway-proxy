# Claude Code Gateway Proxy

让 **Claude Code** 通过 **LiteLLM** 连接**任何 OpenAI 兼容网关**（例如学校的模型中转站、One-API / New-API 等自建网关）。

Claude Code 只会说「Anthropic 协议」，而很多网关只支持「OpenAI 协议」。这个项目在本地起一个代理，把两者的协议自动互译。

## 为什么需要它

| 一方 | 说的协议 | 端点 |
|---|---|---|
| Claude Code | Anthropic | `POST /v1/messages` |
| 你的网关（多数自建/学校中转） | OpenAI | `POST /v1/chat/completions` |

两者语言不通，直接把 Claude Code 指向网关会报 **「模型不存在 / 无权访问」**。

这个代理就是一个「翻译官」，跑在本地 `127.0.0.1:4000`：

```
Claude Code ──Anthropic──▶ 本地 LiteLLM 代理 ──OpenAI──▶ 你的网关
(127.0.0.1:4000)              （协议翻译）
```

## 快速开始

### 1. 准备环境

需要 Python 3.9+。

```bash
git clone <你的仓库地址>
cd claude-code-gateway-proxy
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

### 2. 填写密钥

```bash
cp .env.example .env
```

编辑 `.env`，填入：

| 变量 | 说明 |
|---|---|
| `GATEWAY_BASE_URL` | 你网关的地址（以 `/v1` 结尾） |
| `GATEWAY_API_KEY` | 你网关的 API Key |
| `LITELLM_MASTER_KEY` | 本地代理自己的访问密码（自己随便起） |

> ⚠️ `.env` 已被 `.gitignore` 忽略，**绝不会**上传到 git。真 Key 只放这里。

### 3. 填写模型

编辑 `config.yaml` 的 `model_list`，把你网关的模型填进去。

查询网关支持哪些模型：

```bash
curl "$GATEWAY_BASE_URL/models" -H "Authorization: Bearer $GATEWAY_API_KEY"
```

每个条目的含义：

- `model_name`：你在 Claude Code 里看到、并要选择的名字（可随意起）。
- `model`：网关侧**真实**的模型 ID。前缀用 `hosted_vllm/`（走 `/chat/completions` 接口，不触发 Responses API），适用于绝大多数 OpenAI 兼容网关（NewAPI / One-API / vLLM / SGLang 等）。

### 4. 启动

```bash
./start.sh
```

看到 `Uvicorn running on http://127.0.0.1:4000` 就成功了。

### 5. 让 Claude Code 用它

编辑 `~/.claude/settings.json`，在 `env` 里加：

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:4000",
    "ANTHROPIC_AUTH_TOKEN": "sk-litellm-local",
    "ANTHROPIC_MODEL": "my-model-alias"
  }
}
```

- `ANTHROPIC_AUTH_TOKEN`：填你在 `.env` 里设的 `LITELLM_MASTER_KEY`。
- `ANTHROPIC_MODEL`：填 `config.yaml` 里 `model_name` 对应的名字。

然后**完全退出并重开 Claude Code**，用 `/model` 选择你的模型即可。

> 💡 如果你用 **cc-switch** 之类的切换工具：新建/编辑一个供应商，**Base URL 填 `http://127.0.0.1:4000`**，**API Key 填你的 `LITELLM_MASTER_KEY`**，模型填 `config.yaml` 里的 `model_name`。

## 验证是否成功

```bash
curl http://127.0.0.1:4000/v1/messages \
  -H "x-api-key: sk-litellm-local" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{"model":"my-model-alias","max_tokens":50,"messages":[{"role":"user","content":"你好"}]}'
```

返回 `200` 且带回复内容，就说明整条链路通了。

## 开机自启（macOS）

见 `deploy/macos/com.example.litellm-proxy.plist`。

1. 把文件里 `/Users/YOUR_USERNAME/...` 两处路径改成你的实际路径。
2. 复制到 `~/Library/LaunchAgents/` 并加载：

```bash
cp deploy/macos/com.example.litellm-proxy.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.litellm-proxy.plist
```

这样开机自动启动、崩溃自动重启。

## 示例：同济 AGI 网关

以同济大学 AGI 网关（`https://agi.tongji.edu.cn/v1`）为例，它支持的模型有：

- `DeepSeek-V4.1-Flash`
- `GLM-5.3`、`GLM-5.3-Flash`
- `Qwen3.8-Flash-Next`、`Qwen3.8-27B`
- `MiMo-V2.6-Pro`、`MiMo-V2.6-Flash`
- `MiniMax-M3.1-Flash`

对应的 `config.yaml`：

```yaml
model_list:
  - model_name: DeepSeek-V4.1-Flash
    litellm_params:
      model: hosted_vllm/DeepSeek-V4.1-Flash
      api_base: os.environ/GATEWAY_BASE_URL
      api_key: os.environ/GATEWAY_API_KEY
      timeout: 600
```

对应的 `.env`：

```
GATEWAY_BASE_URL=https://agi.tongji.edu.cn/v1
GATEWAY_API_KEY=你的同济key
LITELLM_MASTER_KEY=sk-litellm-local
```

## 常见问题

- **报 403「当前网络环境不支持」**：说明当前不在允许的网络环境里（通常要连校园网或学校 VPN），连上即可。
- **报「模型不存在 / 无权访问」**：模型名对不上。确认 `config.yaml` 里的 `model` 是网关真实模型 ID，且 Claude Code 里选的是 `model_name`。
- **端口 4000 被占用**：`lsof -iTCP:4000 -sTCP:LISTEN` 看是谁占用，或改用其他端口（改 `start.sh` 里的 `--port`，同时改 Claude Code 里的 `ANTHROPIC_BASE_URL`）。

## 安全提醒

- **绝对不要**把真实 Key 提交到 git（放 `.env`，已被忽略）。
- 提交前可用 `git grep -n "sk-"` 自查是否漏了密钥。
- 若 Key 曾经泄露，建议去网关后台**重置/吊销**。

## License

[MIT](./LICENSE)
