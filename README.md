# AgentsSettings

Claude Code と Codex CLI の両方に共通の設定（Skills / Subagents / Hooks / Permissions / MCP / メイン指示書）を **1 つのソースから両方のエージェントに自動展開する** 汎用デプロイサービス。

```
.agents/    ← ここに書く（1ソース）
   ↓ agents-deploy
.claude/  +  .codex/  +  CLAUDE.md  +  AGENTS.md
```

両エージェントは設定の置き場所とフォーマットが異なるため、ファイル名・YAML 構造・hook イベント名・キー階層などをそれぞれの公式仕様に合わせて自動変換します。

---

## クイックスタート

### 1. インストール（一度だけ）

```bash
# 1) クローン
git clone <this-repo> ~/path/to/AgentsSettings

# 2) 依存をインストール (jq は brew/apt で、python パッケージは pip で)
brew install jq                  # macOS の場合
pip install tomlkit pyyaml

# 3) PATH 上にシンボリックリンクを作成
cd ~/path/to/AgentsSettings
./src/install.sh                 # ~/.local/bin/agents-deploy に symlink を作る

# 4) PATH に ~/.local/bin が無ければ追加
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc

# 5) 動作確認
agents-deploy --check-deps
```

### 2. 任意のプロジェクトで使う

```bash
cd /path/to/myproject
mkdir -p .agents
# .agents/ 配下に設定を書く（次節「設定の書き方」を参照）
agents-deploy                    # CWD の .agents/ を読み、CWD 直下に展開
```

実行すると同ディレクトリに以下が生成されます:

```
myproject/
├── .agents/          (あなたが書いたソース)
├── CLAUDE.md         ← Claude Code 用の指示書
├── AGENTS.md         ← Codex 用の指示書
├── .claude/          ← Claude Code 用
│   ├── settings.json
│   ├── skills/
│   ├── agents/
│   └── hooks/scripts/
└── .codex/           ← Codex 用
    ├── config.toml
    ├── hooks.json
    ├── rules/default.rules
    ├── skills/
    ├── agents/        (TOML)
    └── hooks/scripts/
```

`.claude/` `.codex/` `CLAUDE.md` `AGENTS.md` は **生成物** なので `.gitignore` に追加することを推奨します。

---

## 設定の書き方

### `.agents/` 全体構成

```
.agents/
├── AGENTS.md                   # メイン指示書 (両ツール共通)
├── skills/
│   └── <skill-name>/
│       ├── SKILL.md
│       └── (assets/, scripts/ 等は丸ごと両側にコピーされる)
├── agents/
│   └── <agent-name>.md         # Claude subagent 形式
├── hooks/
│   ├── events.json             # Claude settings.json の hooks と同形式
│   └── scripts/                # フックスクリプト本体
│       └── <name>.sh
├── permissions.yaml            # コマンド許可/拒否 (中立記述)
├── mcp.json                    # MCP サーバ定義
└── settings/                   # ツール専用の追加設定 (最後にマージ)
    ├── claude.json             # → .claude/settings.json
    ├── codex.toml              # → .codex/config.toml
    └── codex-agents.toml       # 個別 subagent の Codex 固有上書き
```

### 1) `AGENTS.md` — メイン指示書

両ツールの指示書（Claude の `CLAUDE.md`、Codex の `AGENTS.md`）に同じ内容が展開されます。差分が必要な箇所は HTML コメントで囲みます。

```markdown
# My Project

このプロジェクトでは… (共通)

<!-- claude-only:start -->
Claude Code 専用の指示
<!-- claude-only:end -->

<!-- codex-only:start -->
Codex 専用の指示
<!-- codex-only:end -->
```

### 2) `skills/<name>/SKILL.md` — スキル

Claude 形式の frontmatter で書きます。Codex 側にデプロイされる際に `metadata.short-description` が自動追加されます。

```markdown
---
name: my-skill
description: When the user asks about X, do Y…
---

# My skill

手順を Markdown で書く…
```

スキル配下の任意のファイル（`scripts/`, `assets/`, Codex UI 用の `agents/openai.yaml` など）は両側に丸ごとコピーされます。

### 3) `agents/<name>.md` — Subagent (チームエージェント)

Claude subagent の `.md` 形式 1 つから、Claude `.claude/agents/<n>.md` と Codex `.codex/agents/<n>.toml` の両方を生成します。

```markdown
---
name: code-reviewer
description: Reviews code for security and quality issues
tools: [Read, Grep, Bash]
model: opus
color: blue
---
You are a code review specialist.
Focus on correctness, security regressions, and missing tests.
```

- Claude: そのままコピー
- Codex: TOML に変換され、本文は `developer_instructions` に格納される
- Codex 固有のフィールド (`model_reasoning_effort`, `sandbox_mode`, `nickname_candidates` 等) は `settings/codex-agents.toml` で agent 名ごとに指定

### 4) `hooks/events.json` + `hooks/scripts/`

Claude `settings.json` の `hooks` セクションと同じ形式で書きます。

```json
{
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        { "type": "command", "command": "hooks/scripts/pre-bash.sh" }
      ]
    }
  ],
  "Notification": [
    { "hooks": [{ "type": "command", "command": "hooks/scripts/notify.sh" }] }
  ]
}
```

- Claude: `settings.json.hooks` へ jq でマージ。全イベントが反映される
- Codex: 対応イベント (`PreToolUse` / `PostToolUse` / `UserPromptSubmit` / `SessionStart` / `Stop`) のみ `.codex/hooks.json` に書き出され、未対応イベント (`Notification` 等) は警告ログ付きでスキップ
- `hooks/scripts/` 配下は両方の `.claude/hooks/scripts/` と `.codex/hooks/scripts/` にコピー

### 5) `permissions.yaml` — Bash コマンド許可/拒否

中立記述で書き、Claude / Codex の両形式に変換されます。

```yaml
allow:
  - command: ["git", "status"]
    style: prefix
  - command: ["ls"]
    style: prefix
deny:
  - command: ["rm", "-rf", "/"]
    style: prefix
```

- Claude: `settings.json.permissions.allow / .deny` に `Bash(git status:*)` 形式の文字列で追加
- Codex: `.codex/rules/default.rules` に `prefix_rule(pattern=["git","status"], decision="allow")` 形式で出力

### 6) `mcp.json` — MCP サーバー

```json
{
  "servers": {
    "linear": { "url": "https://mcp.linear.app/mcp" },
    "github": { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"] }
  }
}
```

- Claude: `settings.json.mcpServers` にマージ
- Codex: `config.toml` の `[mcp_servers.<name>]` テーブルにマージ（コメント・順序保持）

### 7) `settings/claude.json` — Claude 専用設定

`.claude/settings.json` にディープマージされます。**他フェーズの後** に適用されるため、共通の hooks/permissions/mcp も上書きできます。

```json
{
  "model": "opus[1m]",
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "teammateMode": "auto"
}
```

参考: [Claude Code settings 公式](https://code.claude.com/docs/en/settings) / [Agent Teams 公式](https://code.claude.com/docs/en/agent-teams)

### 8) `settings/codex.toml` — Codex 専用設定

`.codex/config.toml` にディープマージされます（tomlkit を使うのでコメント・順序保持）。

```toml
model = "gpt-5.5"
model_reasoning_effort = "high"

[features]
codex_hooks        = true    # lifecycle hooks (experimental)
multi_agent        = true    # subagent collaboration
apps               = true    # ChatGPT Apps / connectors (experimental)
memories           = true
undo               = true
prevent_idle_sleep = true    # (experimental)

[agents]
max_threads = 6
max_depth   = 1

[profiles.safe]
sandbox_mode    = "read-only"
approval_policy = "on-request"
```

参考: [Codex config-reference 公式](https://developers.openai.com/codex/config-reference)

### 9) `settings/codex-agents.toml` — Subagent ごとの Codex 上書き

`agents/<name>.md` から生成される `.codex/agents/<name>.toml` に、Codex 固有のフィールドを agent 名ごとに追加します。

```toml
[code-reviewer]
model = "gpt-5.5"
model_reasoning_effort = "high"
sandbox_mode = "read-only"
nickname_candidates = ["Atlas", "Delta"]

[sample-explorer]
sandbox_mode = "read-only"
```

---

## デプロイの実行

```bash
agents-deploy                                # CWD の .agents/ を展開
agents-deploy --dir=/path/to/project         # 別ディレクトリを指定
agents-deploy --dry-run                      # 書き込まずに差分のみ表示
agents-deploy --only=claude                  # Claude 側だけ
agents-deploy --only=codex                   # Codex 側だけ
agents-deploy --skip=skills,hooks            # 特定アセットをスキップ
agents-deploy --force                        # 既存ファイルを強制上書き
agents-deploy --check-deps                   # 依存ツール確認のみ
agents-deploy --help                         # ヘルプ表示
```

### `--skip` で指定できるアセット名

`instructions` / `skills` / `agents` / `hooks` / `permissions` / `mcp` / `settings`

### デプロイ順とマージの仕組み

1. `instructions` — `AGENTS.md` → `CLAUDE.md` & `AGENTS.md`
2. `skills` — skill ディレクトリを両側にコピー
3. `agents` — subagent .md → Claude .md & Codex .toml
4. `hooks` — Claude `settings.json.hooks` & Codex `hooks.json` + `[features] codex_hooks=true`
5. `permissions` — Claude `settings.json.permissions` & Codex `rules/default.rules`
6. `mcp` — Claude `settings.json.mcpServers` & Codex `config.toml [mcp_servers.*]`
7. `settings` — `.agents/settings/claude.json` / `codex.toml` を **最後にディープマージ** （ツール固有の追加・上書き）

冪等性あり: 同じ `.agents/` で再実行しても、出力に差分は出ません。

---

## アセットごとの変換ルール早見表

| `.agents/` のソース | Claude 出力 | Codex 出力 |
|---|---|---|
| `AGENTS.md` | `CLAUDE.md` | `AGENTS.md` |
| `skills/<n>/SKILL.md` | `.claude/skills/<n>/SKILL.md` | `.codex/skills/<n>/SKILL.md` + `metadata.short-description` |
| `skills/<n>/*` (その他) | `.claude/skills/<n>/` 丸コピー | `.codex/skills/<n>/` 丸コピー |
| `agents/<n>.md` | `.claude/agents/<n>.md` | `.codex/agents/<n>.toml` (TOML 変換) |
| `hooks/events.json` | `settings.json.hooks` にマージ | `.codex/hooks.json` (対応イベントのみ) |
| `hooks/scripts/*` | `.claude/hooks/scripts/` | `.codex/hooks/scripts/` |
| `permissions.yaml` | `settings.json.permissions` | `.codex/rules/default.rules` |
| `mcp.json` | `settings.json.mcpServers` | `config.toml [mcp_servers.*]` |
| `settings/claude.json` | `.claude/settings.json` (deep merge) | — |
| `settings/codex.toml` | — | `.codex/config.toml` (deep merge) |
| `settings/codex-agents.toml` | — | 各 agent の `.codex/agents/<n>.toml` に上書き追加 |

---

## 依存ツール

| ツール | 用途 | インストール |
|---|---|---|
| `bash` | shell | OS 標準 |
| `jq` | JSON マージ | `brew install jq` / `apt install jq` |
| `python3` >= 3.9 | TOML / YAML 操作 | OS 標準 / `brew install python` |
| `tomlkit` | TOML in-place 編集 (コメント保持) | `pip install tomlkit` |
| `pyyaml` | YAML frontmatter | `pip install pyyaml` |
| `shasum` / `sha256sum` | sha256 | OS 標準 |

`agents-deploy --check-deps` で過不足を確認できます。

---

## このリポ自体の構成

- `.agents/` — **ドッグフード用サンプル設定**。このリポで `agents-deploy` を実行すると自分自身に展開され、動作確認になる
- `src/` — デプロイスクリプト本体
  - `src/deploy.sh` — エントリポイント
  - `src/install.sh` — `~/.local/bin/agents-deploy` への symlink 作成
  - `src/lib/deploy_*.sh` — アセット種別ごとのデプロイロジック
  - `src/tools/*.py` — YAML / TOML 変換用 Python ヘルパー

## 参考リンク

- [Claude Code settings](https://code.claude.com/docs/en/settings)
- [Claude Code Agent Teams](https://code.claude.com/docs/en/agent-teams)
- [Claude Code Sub-agents](https://code.claude.com/docs/en/sub-agents)
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks)
- [Codex config-reference](https://developers.openai.com/codex/config-reference)
- [Codex Subagents](https://developers.openai.com/codex/subagents)
- [Codex Hooks](https://developers.openai.com/codex/hooks)
