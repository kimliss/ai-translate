# AI Translate

AI Translate 是一个轻量级命令行工具，用于解析 Xcode `.xcstrings` 文件，调用 OpenAI 的 ChatGPT 模型完成多语言翻译，并将结果保存回符合 `xcstrings` 规范的 JSON 格式文件中。

本工具目前默认使用 **ChatGPT-4**。虽然 ChatGPT-3.5 成本更低，但翻译质量不足以满足实际需求，因此未提供通过命令行参数选择模型的功能。这一限制旨在避免因低质量自动翻译而降低 Apple 平台应用的整体用户体验。

⚠️ **重要提示**：即使使用 ChatGPT-4，翻译结果也几乎不可能完全正确。强烈建议在生产环境中由专业人工译者进行校对和验证。

---

## 功能特性

- 支持从 `.xcstrings` 文件中提取文本，并生成多语言翻译。
- 支持通过 API Key 或 `.env` 文件进行配置。
- 提供并发控制以提升翻译效率。
- 默认保留输入文件的备份，避免误操作导致数据丢失。
- 可强制覆盖已有翻译，适合更新翻译场景。

### 尚未支持的功能
当前实现覆盖了开发者常用的场景，但并未完整支持 `xcstrings` 的全部特性，例如：
- 复数（plural）字符串
- 按设备（device variation）区分的字符串

欢迎通过 Pull Request 提交补充和改进。

---

## 安装

使用以下脚本安装或更新：

```bash
# 安装或更新
curl -fsSL https://raw.githubusercontent.com/kimliss/ai-translate/refs/heads/main/install.sh | bash

# 卸载
curl -fsSL https://raw.githubusercontent.com/kimliss/ai-translate/refs/heads/main/install.sh | bash install.sh uninstall
````

---

## 使用方法

在项目根目录执行：

```bash
# 使用命令行参数配置
ai-translate /path/to/Localizable.xcstrings -o <your-openai-API-key> -v -l de,es,fr,he,it,ru,hi,en-GB

# 使用环境变量配置
curl -o .env https://raw.githubusercontent.com/kimliss/ai-translate/refs/heads/main/.env.example
echo ".env" >> .gitignore
ai-translate /path/to/Localizable.xcstrings
```

---

## 命令行参数

执行 `ai-translate --help` 查看完整说明：

```
OVERVIEW: A command line tool that performs translation of xcstrings

VERSION: 1.0.0

USAGE: ai-translate <input-file> [options]

ARGUMENTS:
  <input-file>             输入的 .xcstrings 文件路径

OPTIONS:
  -l, --languages <codes>  逗号分隔的语言代码（需与 xcstrings 语言代码一致）
  -o, --open-ai-key <key>  OpenAI API Key，获取方式：https://platform.openai.com/api-keys
  --host <host>            OpenAI API 代理地址
  -m, --model <model>      指定模型，例如：gpt-3.5-turbo, gpt-4o-mini, gpt-4o
  -c, --concurrency <n>    并发翻译任务数（默认：5）
  -v, --verbose            输出详细日志
  -s, --skip-backup        跳过自动备份输入文件
  -f, --force              强制重新翻译所有字符串，即使已有翻译
  -h, --help               显示帮助信息
```

---

## 贡献

欢迎提交 Issue 或 Pull Request 来报告问题或改进功能。

---

## 许可协议

本项目采用 [MIT License](LICENSE)。

```