# AI Translate

English | [中文](./README.zh-CN.md)

AI Translate is a lightweight command-line tool that parses Xcode `.xcstrings` files, uses OpenAI's ChatGPT model to generate translations, and writes results back in the `xcstrings` JSON format.

This tool is hardcoded to use **ChatGPT-4**. While ChatGPT-3.5 is cheaper, it does not provide adequate translation quality, so the option to switch models via CLI has been deliberately omitted. This ensures the tool does not contribute to the spread of poor translations in Apple platform apps.  

⚠️ **Important:** Even with ChatGPT-4, translations will almost certainly not be perfect. It is strongly recommended to have a qualified human translator review results before release.

---

## Features

- Parse `.xcstrings` files and generate translations for multiple languages.
- Configure via API key or `.env` file.
- Concurrency control to speed up translation.
- Automatic backup of input files (optional skip).
- Force re-translation of existing strings when needed.

### Not yet supported
This tool currently covers features used by the author, but does **not** fully support all `xcstrings` functionality, such as:
- Plural strings
- Device-variant strings

Pull requests are welcome to extend support.

---

## Installation

Run the following script to install or update:

```bash
# Install or update
curl -fsSL https://raw.githubusercontent.com/kimliss/ai-translate/refs/heads/main/install.sh | bash

# Uninstall
curl -fsSL https://raw.githubusercontent.com/kimliss/ai-translate/refs/heads/main/install.sh | bash install.sh uninstall
````

---

## Usage

From the repo root directory:

```bash
# With command-line arguments
ai-translate /path/to/Localizable.xcstrings -o <your-openai-API-key> -v -l de,es,fr,he,it,ru,hi,en-GB

# With environment variables
curl -o .env https://raw.githubusercontent.com/kimliss/ai-translate/refs/heads/main/.env.example
echo ".env" >> .gitignore
ai-translate /path/to/Localizable.xcstrings
```

---

## Command Line Options

Use `ai-translate --help` for details:

```
OVERVIEW: A command line tool that performs translation of xcstrings

VERSION: 1.0.0

USAGE: ai-translate <input-file> [options]

ARGUMENTS:
  <input-file>             Path to the .xcstrings file

OPTIONS:
  -l, --languages <codes>  Comma-separated list of language codes (must match xcstrings codes)
  -o, --open-ai-key <key>  Your OpenAI API key (see: https://platform.openai.com/api-keys)
  --host <host>            OpenAI API proxy host
  -m, --model <model>      Model to use (e.g. gpt-3.5-turbo, gpt-4o-mini, gpt-4o)
  -c, --concurrency <n>    Max number of concurrent translation tasks (default: 5)
  -v, --verbose            Enable verbose logging
  -s, --skip-backup        Skip automatic backup of the input file
  -f, --force              Force re-translation of all strings, even if translations exist
  -h, --help               Show help information
```

---

## Contributing

Issues and Pull Requests are welcome for bug reports, new features, or improvements.

---

## License

This project is licensed under the [MIT License](LICENSE).