# Claw Code

一个类似 Codex / Claude Code CLI 的本地代码智能体工具。  
核心实现位于 Rust 工作区 [`rust/`](/home/yang/Downloads/clawcode/rust)，仓库根目录提供了启动脚本和全局命令封装。

## 功能

- 支持 `Poe` 模式，直接走 Poe 的 Anthropic 兼容接口
- 支持 `local` 模式，连接本地 OpenAI 兼容模型服务
- 当前终端所在目录就是智能体工作区
- 支持交互式会话和单次 prompt
- 支持类似 Codex 的动态状态栏，实时显示当前分析/搜索/修改阶段
- 默认使用 `workspace-write`，执行命令仍需人工审批
- 提供 `claw`、`claw-poe`、`claw-local`、`claw-local-server`、`claw-doctor` 命令

## 目录说明

- [`rust/`](/home/yang/Downloads/clawcode/rust)：Rust CLI 主体
- [`start.sh`](/home/yang/Downloads/clawcode/start.sh)：统一启动入口
- [`install-commands.sh`](/home/yang/Downloads/clawcode/install-commands.sh)：安装全局命令到 `~/.local/bin`
- [`.env.example`](/home/yang/Downloads/clawcode/.env.example)：配置模板

## 安装

### 1. 编译 CLI

```bash
cd /home/yang/Downloads/clawcode/rust
cargo build --release
```

编译产物在：

```bash
/home/yang/Downloads/clawcode/rust/target/release/claw
```

注意：`cargo build --release` 只会生成二进制，不会自动把 `claw` 安装成全局命令。

### 2. 安装全局启动命令

```bash
cd /home/yang/Downloads/clawcode
chmod +x start.sh install-commands.sh
./install-commands.sh
```

这会在 `~/.local/bin` 下创建这些命令：

- `claw`
- `claw-poe`
- `claw-local`
- `claw-local-server`
- `claw-doctor`

如果执行 `claw` 提示 `command not found`，先把 `~/.local/bin` 加入 `PATH`：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

如果你希望以后所有 bash/conda 终端都能直接用，建议把这行写进 `~/.bashrc`。

### 3. 准备配置

```bash
cd /home/yang/Downloads/clawcode
cp .env.example .env
```

然后按你的实际情况修改 [`.env`](/home/yang/Downloads/clawcode/.env)。

## 使用

- 先 `cd` 到你要操作的项目目录
- 然后执行 `claw` / `claw-poe` / `claw-local`
- 智能体会把“当前目录”当成工作区

例如：

```bash
cd /path/to/your/project
claw
```

## Poe 模式

适合直接使用 Poe API，稳定性最好，配置最简单。

### `.env` 最少需要

```bash
CLAW_PROVIDER=poe
CLAW_MODEL=claude-sonnet-4-6
POE_API_KEY=你的_poe_api_key
POE_BASE_URL=https://api.poe.com
CLAW_PERMISSION_MODE=workspace-write
```

### 启动

交互式：

```bash
cd /path/to/your/project
claw-poe
```

单次任务：

```bash
cd /path/to/your/project
claw-poe "summarize this repository"
```

如果 [`.env`](/home/yang/Downloads/clawcode/.env) 里设置了 `CLAW_PROVIDER=poe`，也可以直接用：

```bash
cd /path/to/your/project
claw
```

## 本地模型模式

适合使用你自己机器上的模型目录，例如 `/home/yang/Downloads/pretrained/`。

### 1. 准备 Python 环境

建议单独建一个 conda 环境用于本地模型服务：

```bash
conda create -y -p /home/yang/miniconda3/envs/claw-local python=3.10 "numpy<2"
conda activate /home/yang/miniconda3/envs/claw-local
pip install --upgrade pip
pip install "transformers[serving]" accelerate safetensors sentencepiece requests openai
```

`numpy<2` 是为了兼容一部分旧的 `torch` / CUDA / `transformers` 组合。

### 2. `.env` 推荐配置

```bash
CLAW_PROVIDER=local
OPENAI_API_KEY=local-test-key
OPENAI_BASE_URL=http://127.0.0.1:8011/v1
LOCAL_MODEL_ROOT=/home/yang/Downloads/pretrained
LOCAL_MODEL_REF=/home/yang/Downloads/pretrained/Qwen3-4B
LOCAL_ALLOWED_TOOLS=read,glob,grep,edit,write,TodoWrite
CLAW_PERMISSION_MODE=workspace-write
LOCAL_SERVER_USE_ACTIVE_CONDA=true
```

如果你想固定某个 conda 环境，不跟随当前 shell，额外设置：

```bash
CONDA_ENV_PREFIX=/home/yang/miniconda3/envs/claw-local
```

### 3. 启动本地模型服务

```bash
claw-local-server
```

或者指定模型：

```bash
claw-local-server --local-model /home/yang/Downloads/pretrained/Qwen3-4B
```

默认情况下：

- 如果当前已经激活了非 `base` 的 conda 环境，优先使用当前环境
- 否则回退到 `CONDA_ENV_PREFIX`
- 如果端口被占用，会自动寻找下一个可用端口

### 4. 使用本地模式

交互式：

```bash
cd /path/to/your/project
claw-local
```

单次任务：

```bash
cd /path/to/your/project
claw-local "review this repository"
```

如果 [`.env`](/home/yang/Downloads/clawcode/.env) 里设置了 `CLAW_PROVIDER=local`，也可以直接：

```bash
cd /path/to/your/project
claw
```

如果你希望本地模型也能执行 `bash`，需要显式放开：

```bash
claw-local --allowedTools read,glob,grep,edit,write,TodoWrite,bash
```

## 常用命令

```bash
claw
claw-poe
claw-local
claw-doctor
claw-local --list-local-models
claw-local-server
claw-local-server --local-model /home/yang/Downloads/pretrained/Qwen3-4B
```

也可以直接用启动脚本：

```bash
./start.sh build
./start.sh doctor
./start.sh poe-cli
./start.sh poe-prompt "say hello"
./start.sh local-server
./start.sh local-cli
./start.sh local-prompt "summarize this repo"
```

## 审批与权限

默认权限模式是：

```bash
--permission-mode workspace-write
```

这表示：

- 智能体可以读写当前工作区文件
- 执行命令时仍会弹出人工审批
- 不会默认无条件执行高风险操作

当命令需要额外审批时，当前版本支持：

- `y`：只放行这一次
- `a`：本次会话里始终放行这类工具
- `s`：本次会话里放行后续所有升级审批

如果你希望在 `workspace-write` 模式下默认就信任 `bash`，减少审批次数，可以在 [`.env`](/home/yang/Downloads/clawcode/.env) 里设置：

```bash
CLAW_TRUST_BASH_IN_WORKSPACE_WRITE=true
```

这样会在当前会话开始时自动把 `bash` 视为“已批准过的升级工具”，更接近 Codex 的交互方式。

如果需要只读模式：

```bash
claw --permission-mode read-only
```

## 排错

### `claw: command not found`

说明全局命令没进 `PATH`。先执行：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

然后再试：

```bash
claw --help
```

### 为什么在一个终端能用，另一个终端不能用

通常不是编译问题，而是 shell 启动文件不同：

- 有的终端会读取 `~/.profile`
- 有的终端只读取 `~/.bashrc`
- 如果 `~/.local/bin` 只在其中一个文件里被加入 `PATH`，表现就会不一致

### `cargo build --release` 之后为什么还是不能直接运行 `claw`

因为这一步只生成了 Rust 二进制，没有安装全局启动命令。  
你还需要运行：

```bash
cd /home/yang/Downloads/clawcode
./install-commands.sh
export PATH="$HOME/.local/bin:$PATH"
```

### 如何确认当前配置是否正确

```bash
claw-doctor
```

它会输出当前实际使用的：

- `CLAW_BIN`
- `CLAW_PROVIDER`
- `CLAW_MODEL`
- `CONDA_ENV_PREFIX`
- 本地模型相关配置

## 最短上手流程

### Poe

```bash
cd /home/yang/Downloads/clawcode
cp .env.example .env
# 编辑 .env，填入 POE_API_KEY
cd rust && cargo build --release
cd ..
./install-commands.sh
export PATH="$HOME/.local/bin:$PATH"
cd /path/to/your/project
claw-poe
```

### Local

```bash
conda create -y -p /home/yang/miniconda3/envs/claw-local python=3.10 "numpy<2"
conda activate /home/yang/miniconda3/envs/claw-local
pip install "transformers[serving]" accelerate safetensors sentencepiece requests openai

cd /home/yang/Downloads/clawcode
cp .env.example .env
cd rust && cargo build --release
cd ..
./install-commands.sh
export PATH="$HOME/.local/bin:$PATH"
claw-local-server --local-model /home/yang/Downloads/pretrained/Qwen3-4B

# 另开一个终端
cd /path/to/your/project
claw-local
```
