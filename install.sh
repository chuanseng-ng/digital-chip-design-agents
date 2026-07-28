#!/usr/bin/env bash
# install.sh — installs digital-chip-design-agents plugins
#
# Usage:
#   bash install.sh                         # auto-detect installed agents + confirm
#   bash install.sh --yes                   # auto-detect, no confirmation prompt
#   bash install.sh --ide claude            # Claude Code (explicit)
#   bash install.sh --ide copilot           # GitHub Copilot (.github/ in cwd)
#   bash install.sh --ide gemini            # Gemini Code Assist (GEMINI.md in cwd)
#   bash install.sh --ide gemini --global   # Gemini global (~/GEMINI.md)
#   bash install.sh --ide opencode          # OpenCode (opencode.json in cwd)
#   bash install.sh --ide opencode --global # OpenCode global (~/.config/opencode/)
#   bash install.sh --ide codex             # OpenAI Codex CLI (AGENTS.md in cwd)
#   bash install.sh --ide codex --global    # OpenAI Codex CLI global (~/.codex/instructions.md)
#   bash install.sh --ide all               # Claude Code + all four other IDEs (copilot, gemini, opencode, codex)
#
# With no --ide flag the script detects which of the five supported agents
# (claude, codex, opencode, gemini, copilot) are present and installs to them
# after a confirmation prompt. Passing --ide bypasses detection.
#
# Works on macOS, Linux, and Git Bash / MSYS2 on Windows.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE="digital-chip-design-agents"
# Each plugin's cache version is read from its own .claude-plugin/plugin.json
# below, so plugins at different versions land in the correct path.

# ── Parse flags ───────────────────────────────────────────────────────────────
IDE=""
GLOBAL="false"
YES="false"
while [[ $# -gt 0 ]]; do
  case $1 in
    --ide)
      # Guard against a trailing `--ide` so `set -u` doesn't abort on $2 before
      # the user sees a usage message.
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --ide requires a value: claude|copilot|gemini|opencode|codex|all|auto"
        exit 1
      fi
      IDE="$2"; shift 2
      ;;
    --global)
      GLOBAL="true"; shift
      ;;
    --yes|-y)
      YES="true"; shift
      ;;
    -h|--help)
      echo "Usage: bash install.sh [--ide claude|copilot|gemini|opencode|codex|all] [--global] [--yes]"
      echo "  With no --ide, detects installed agents and installs to them after confirmation."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: bash install.sh [--ide claude|copilot|gemini|opencode|codex|all] [--global] [--yes]"
      exit 1
      ;;
  esac
done

if [[ -n "$IDE" && "$IDE" != "auto" ]]; then
  case "$IDE" in
    claude|copilot|gemini|opencode|codex|all) ;;
    *)
      echo "ERROR: --ide must be one of: claude, copilot, gemini, opencode, codex, all, auto"
      exit 1
      ;;
  esac
fi

# ── Shared sanity check ───────────────────────────────────────────────────────
if [[ ! -f "$REPO_DIR/.claude-plugin/marketplace.json" ]]; then
  echo "ERROR: Cannot locate repo root. Ensure install.sh is inside the cloned repo."
  exit 1
fi

# ── Detection (read-only) ─────────────────────────────────────────────────────
# A target counts as installed if its CLI is on PATH or its config dir exists.
# Mirrors bin/detect.mjs. Copilot is project-scoped, so it is detected only via
# the gh / copilot CLI.
is_installed() {
  case "$1" in
    claude)   command -v claude   >/dev/null 2>&1 || [[ -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ]] ;;
    codex)    command -v codex    >/dev/null 2>&1 || [[ -d "$HOME/.codex" ]] ;;
    opencode) command -v opencode >/dev/null 2>&1 || [[ -d "$HOME/.config/opencode" ]] ;;
    gemini)   command -v gemini   >/dev/null 2>&1 || [[ -d "$HOME/.gemini" ]] ;;
    copilot)  command -v copilot  >/dev/null 2>&1 || command -v gh >/dev/null 2>&1 ;;
  esac
}

# Where each target writes, so the confirmation shows repo vs $HOME vs config dir.
# Mirrors the destinations in bin/detect.mjs and the per-IDE install blocks below.
destination_for() {
  case "$1" in
    claude)   echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude} (global plugin cache)" ;;
    codex)    [[ "$GLOBAL" == "true" ]] && echo "$HOME/.codex/instructions.md" || echo "$PWD/AGENTS.md" ;;
    opencode) [[ "$GLOBAL" == "true" ]] && echo "$HOME/.config/opencode/config.json" || echo "$PWD/opencode.json" ;;
    gemini)   [[ "$GLOBAL" == "true" ]] && echo "$HOME/GEMINI.md" || echo "$PWD/GEMINI.md" ;;
    copilot)  echo "$PWD/.github" ;;
  esac
}

# ── Plugin list ───────────────────────────────────────────────────────────────
PLUGINS=(
  "chip-design-architecture"
  "chip-design-rtl"
  "chip-design-verification"
  "chip-design-formal"
  "chip-design-synthesis"
  "chip-design-dft"
  "chip-design-sta"
  "chip-design-hls"
  "chip-design-pd"
  "chip-design-soc"
  "chip-design-memory-ip"
  "chip-design-compiler"
  "chip-design-firmware"
  "chip-design-fpga"
  "chip-design-infrastructure"
  "chip-design-meta"
)

# ── Plugin → source directory mapping ────────────────────────────────────────
declare -A PLUGIN_DIRS=(
  ["chip-design-architecture"]="architecture"
  ["chip-design-rtl"]="rtl-design"
  ["chip-design-verification"]="verification"
  ["chip-design-formal"]="formal"
  ["chip-design-synthesis"]="synthesis"
  ["chip-design-dft"]="dft"
  ["chip-design-sta"]="sta"
  ["chip-design-hls"]="hls"
  ["chip-design-pd"]="pd"
  ["chip-design-soc"]="soc"
  ["chip-design-memory-ip"]="memory-ip"
  ["chip-design-compiler"]="compiler"
  ["chip-design-firmware"]="firmware"
  ["chip-design-fpga"]="fpga"
  ["chip-design-infrastructure"]="infrastructure"
  ["chip-design-meta"]="meta"
)

# ── Build the selection set ───────────────────────────────────────────────────
declare -A SEL=()
ALL_TARGETS=(claude codex opencode gemini copilot)

if [[ -z "$IDE" || "$IDE" == "auto" ]]; then
  echo "Detecting installed AI coding agents..."
  echo ""
  detected=()
  for t in "${ALL_TARGETS[@]}"; do
    if is_installed "$t"; then
      detected+=("$t"); echo "  [found] $t -> $(destination_for "$t")"
    else
      echo "  [  -  ] $t"
    fi
  done
  if [[ ${#detected[@]} -eq 0 ]]; then
    echo ""
    echo "No supported agents detected. Install one explicitly with:"
    echo "  bash install.sh --ide claude   (or copilot|gemini|opencode|codex|all)"
    exit 0
  fi
  if [[ "$YES" != "true" && -t 0 ]]; then
    echo ""
    read -r -p 'Install to all detected targets? [Y/n] (or list a subset, e.g. "claude,codex"): ' ans
    ans="$(echo "$ans" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    case "$ans" in
      ""|y|yes) for t in "${detected[@]}"; do SEL[$t]=1; done ;;
      n|no)     echo "Aborted."; exit 0 ;;
      *)
        IFS=',' read -ra picks <<< "$ans"
        for p in "${picks[@]}"; do
          for t in "${detected[@]}"; do [[ "$p" == "$t" ]] && SEL[$t]=1; done
        done
        ;;
    esac
  else
    for t in "${detected[@]}"; do SEL[$t]=1; done
    echo ""
    echo "Installing to all detected targets."
  fi
elif [[ "$IDE" == "all" ]]; then
  for t in "${ALL_TARGETS[@]}"; do SEL[$t]=1; done
else
  SEL[$IDE]=1
fi

if [[ ${#SEL[@]} -eq 0 ]]; then
  echo "Nothing selected. Aborted."
  exit 0
fi

# ── python3 is required for every target in the shell installer ───────────────
# (Even the Claude block reads plugin versions and merges settings.json via
# python3.) The Python-free path is the npm installer: npx digital-chip-design-agents.
if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 is required by install.sh but was not found in PATH."
  echo "  For a Python-free install, use: npx digital-chip-design-agents"
  exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Claude Code install
# ═══════════════════════════════════════════════════════════════════════════════
if [[ -n "${SEL[claude]:-}" ]]; then

  # Locate Claude config dir
  if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    CLAUDE_DIR="$CLAUDE_CONFIG_DIR"
  elif [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* || "$OSTYPE" == win32* ]]; then
    CLAUDE_DIR="${USERPROFILE}/.claude"
  else
    CLAUDE_DIR="${HOME}/.claude"
  fi

  CACHE_DIR="$CLAUDE_DIR/plugins/cache/$MARKETPLACE"
  SETTINGS="$CLAUDE_DIR/settings.json"

  echo "Claude config : $CLAUDE_DIR"
  echo "Plugin cache  : $CACHE_DIR"
  echo ""

  if [[ ! -d "$CLAUDE_DIR" ]]; then
    echo "ERROR: Claude config directory not found at $CLAUDE_DIR"
    echo "  Make sure Claude Code is installed and has been run at least once."
    exit 1
  fi

  echo "Installing Claude Code plugin cache..."
  for plugin in "${PLUGINS[@]}"; do
    subdir="${PLUGIN_DIRS[$plugin]}"
    src="$REPO_DIR/plugins/$subdir"
    version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$src/.claude-plugin/plugin.json")"
    dest="$CACHE_DIR/$plugin/$version"
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -r "$src/agents"         "$dest/"
    cp -r "$src/skills"         "$dest/"
    cp -r "$src/.claude-plugin" "$dest/"
    [[ -f "$REPO_DIR/README.md" ]] && cp "$REPO_DIR/README.md" "$dest/"
    [[ -f "$REPO_DIR/LICENSE" ]]   && cp "$REPO_DIR/LICENSE"   "$dest/"
    echo "  [OK] $plugin"
  done

  echo ""
  echo "Updating $SETTINGS ..."

  python3 - "$SETTINGS" "$MARKETPLACE" "$REPO_DIR" <<PYEOF
import json, sys, os

settings_path = sys.argv[1]
marketplace   = sys.argv[2]

plugins = [
  "chip-design-architecture", "chip-design-rtl", "chip-design-verification",
  "chip-design-formal",       "chip-design-synthesis", "chip-design-dft",
  "chip-design-sta",          "chip-design-hls",       "chip-design-pd",
  "chip-design-soc",          "chip-design-compiler",  "chip-design-firmware",
  "chip-design-fpga",         "chip-design-infrastructure",
  "chip-design-memory-ip",    "chip-design-meta",
]

cfg = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        cfg = json.load(f)

enabled = cfg.setdefault("enabledPlugins", {})
for p in plugins:
    enabled[f"{p}@{marketplace}"] = True

mp = cfg.setdefault("extraKnownMarketplaces", {})
mp[marketplace] = {
    "source": {"source": "directory", "path": sys.argv[3]}
}

with open(settings_path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")

print(f"  [OK] {len(plugins)} plugins enabled in settings.json")
PYEOF

  # Seed the central memory root from the in-repo memory/ seed (idempotent;
  # copies knowledge.md only if absent, migrates any repo-local runtime data).
  echo ""
  echo "Seeding central memory root..."
  python3 "$REPO_DIR/plugins/infrastructure/skills/memory-keeper/memory_root.py" --init || \
    echo "  [skip] could not seed memory root; run memory_root.py --init manually."

  echo ""
  echo "Done! Restart Claude Code to activate all 16 plugins."

fi  # end Claude Code block

# ═══════════════════════════════════════════════════════════════════════════════
# GitHub Copilot install
# ═══════════════════════════════════════════════════════════════════════════════
if [[ -n "${SEL[copilot]:-}" ]]; then

  echo ""
  echo "Installing GitHub Copilot instructions..."

  python3 - "$REPO_DIR" "$PWD" <<'PYEOF'
import json, os, re, glob, sys, shutil

repo_dir   = sys.argv[1]
target_dir = sys.argv[2]

# Load applyTo glob map
applyto_map = json.load(open(os.path.join(repo_dir, 'ides', 'copilot', 'applyto-map.json')))

# Copy global instructions file
gh_dir = os.path.join(target_dir, '.github', 'instructions')
os.makedirs(gh_dir, exist_ok=True)
shutil.copy(
    os.path.join(repo_dir, 'ides', 'copilot', '.github', 'copilot-instructions.md'),
    os.path.join(target_dir, '.github', 'copilot-instructions.md'),
)

# Generate per-domain instruction files from SKILL.md
skill_files = sorted(glob.glob(os.path.join(repo_dir, 'plugins', '*', 'skills', '*', 'SKILL.md')))
for skill_path in skill_files:
    parts = os.path.normpath(skill_path).split(os.sep)
    domain = parts[parts.index('plugins') + 1]

    applyto = applyto_map.get(domain, '**/*')

    # Strip YAML frontmatter (--- ... ---) from SKILL.md body
    content = open(skill_path, encoding='utf-8').read()
    body = re.sub(r'^---\n.*?\n---\n', '', content, count=1, flags=re.DOTALL).strip()

    out_path = os.path.join(gh_dir, f'{domain}.instructions.md')
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(f'---\napplyTo: "{applyto}"\n---\n\n{body}\n')
    print(f'  [OK] .github/instructions/{domain}.instructions.md')

print(f'\nCopilot: {len(skill_files)} instruction files installed.')
print('Commit .github/ to share domain rules with your team.')
PYEOF

fi  # end Copilot block

# ═══════════════════════════════════════════════════════════════════════════════
# Gemini Code Assist install
# ═══════════════════════════════════════════════════════════════════════════════
if [[ -n "${SEL[gemini]:-}" ]]; then

  echo ""
  echo "Installing Gemini Code Assist context file..."

  if [[ "$GLOBAL" == "true" ]]; then
    GEMINI_TARGET="${HOME}/GEMINI.md"
  else
    GEMINI_TARGET="$PWD/GEMINI.md"
  fi

  python3 - "$REPO_DIR" "$GEMINI_TARGET" <<'PYEOF'
import os, glob, sys

repo_dir = sys.argv[1]
out_path = sys.argv[2]

# Read preamble header
header = open(os.path.join(repo_dir, 'ides', 'gemini', 'gemini-header.md'), encoding='utf-8').read().strip()

lines = [
    '# Digital Chip Design Agents — Gemini Context',
    f'<!-- Generated by install.sh --ide gemini -->',
    f'<!-- Source: {repo_dir} -->',
    '',
    header,
    '',
    '## Domain Knowledge',
    '',
]

skill_files  = sorted(glob.glob(os.path.join(repo_dir, 'plugins', '*', 'skills', '*', 'SKILL.md')))
agent_files  = {
    os.path.basename(os.path.dirname(os.path.dirname(p))): p
    for p in glob.glob(os.path.join(repo_dir, 'plugins', '*', 'agents', '*.md'))
}

for skill_path in skill_files:
    parts = os.path.normpath(skill_path).split(os.sep)
    domain = parts[parts.index('plugins') + 1]

    lines.append(f'### {domain}')
    lines.append('')
    lines.append(f'@{skill_path}')
    if domain in agent_files:
        lines.append(f'@{agent_files[domain]}')
    lines.append('')

with open(out_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines) + '\n')

print(f'  [OK] {out_path}')
print(f'  ({len(skill_files)} domains, {len(skill_files) + len(agent_files)} @-imports)')
PYEOF

fi  # end Gemini block

# ═══════════════════════════════════════════════════════════════════════════════
# OpenCode install
# ═══════════════════════════════════════════════════════════════════════════════
if [[ -n "${SEL[opencode]:-}" ]]; then

  echo ""
  echo "Installing OpenCode config..."

  if [[ "$GLOBAL" == "true" ]]; then
    OPENCODE_TARGET="${HOME}/.config/opencode/config.json"
  else
    OPENCODE_TARGET="$PWD/opencode.json"
  fi

  python3 - "$REPO_DIR" "$OPENCODE_TARGET" "$GLOBAL" <<'PYEOF'
import json, os, glob, re, sys

repo_dir   = sys.argv[1]
target     = sys.argv[2]
is_global  = sys.argv[3] == 'true'

# Mode key / display-name mapping
mode_display = {
    'architecture': ('chip-architecture', 'Chip Architecture Evaluation'),
    'rtl-design':   ('chip-rtl',          'RTL Design (SystemVerilog)'),
    'verification': ('chip-verification', 'Functional Verification (UVM)'),
    'formal':       ('chip-formal',       'Formal Verification (FPV/LEC)'),
    'synthesis':    ('chip-synthesis',    'Logic Synthesis'),
    'dft':          ('chip-dft',          'Design for Test'),
    'sta':          ('chip-sta',          'Static Timing Analysis'),
    'hls':          ('chip-hls',          'High-Level Synthesis'),
    'pd':           ('chip-pd',           'Physical Design'),
    'soc':          ('chip-soc',          'SoC IP Integration'),
    'memory-ip':    ('chip-memory-ip',    'Memory IP Design'),
    'compiler':     ('chip-compiler',     'Compiler Toolchain'),
    'firmware':     ('chip-firmware',     'Embedded Firmware'),
    'fpga':         ('chip-fpga',         'FPGA Emulation'),
}

base = json.load(open(os.path.join(repo_dir, 'ides', 'opencode', 'opencode-base.json')))
modes = {}

agent_files = sorted(glob.glob(os.path.join(repo_dir, 'plugins', '*', 'agents', '*.md')))
for agent_path in agent_files:
    parts = os.path.normpath(agent_path).split(os.sep)
    domain = parts[parts.index('plugins') + 1]

    # Extract description from YAML frontmatter
    content = open(agent_path, encoding='utf-8').read()
    m = re.search(r'^description:\s*>?\s*\n((?:  .+\n)+)', content, re.MULTILINE)
    desc = ' '.join(l.strip() for l in m.group(1).strip().splitlines()) if m else domain
    desc = desc[:120]

    mode_key, mode_name = mode_display.get(domain, (f'chip-{domain}', domain.replace('-', ' ').title()))
    prompt_path = agent_path if os.path.isabs(agent_path) else os.path.relpath(agent_path, os.path.dirname(target))
    modes[mode_key] = {
        'name':        mode_name,
        'description': desc,
        'model':       base.get('model', 'anthropic/claude-sonnet-4-5'),
        'prompt':     '{file:' + prompt_path + '}',
    }

if is_global and os.path.exists(target):
    # Merge modes into existing global config
    existing = json.load(open(target))
    existing.setdefault('mode', {}).update(modes)
    out = existing
else:
    base['mode'] = modes
    out = base
    if is_global:
        os.makedirs(os.path.dirname(target), exist_ok=True)

with open(target, 'w', encoding='utf-8') as f:
    json.dump(out, f, indent=2)
    f.write('\n')

print(f'  [OK] {target} — {len(modes)} modes')
print('  Use /mode chip-<domain> in OpenCode to activate a domain.')
PYEOF

fi  # end OpenCode block

# ═══════════════════════════════════════════════════════════════════════════════
# OpenAI Codex CLI install
# ═══════════════════════════════════════════════════════════════════════════════
if [[ -n "${SEL[codex]:-}" ]]; then

  echo ""
  echo "Installing OpenAI Codex CLI context file..."

  if [[ "$GLOBAL" == "true" ]]; then
    CODEX_TARGET="${HOME}/.codex/instructions.md"
  else
    CODEX_TARGET="$PWD/AGENTS.md"
  fi

  python3 - "$REPO_DIR" "$CODEX_TARGET" <<'PYEOF'
import os, glob, re, sys

repo_dir = sys.argv[1]
out_path = sys.argv[2]

# Read preamble header
header = open(os.path.join(repo_dir, 'ides', 'codex', 'AGENTS.md'), encoding='utf-8').read().strip()

lines = [
    '# Digital Chip Design Agents — Codex CLI Context',
    f'<!-- Generated by install.sh --ide codex -->',
    f'<!-- Source: {repo_dir} -->',
    '',
    header,
    '',
    '## Domain Knowledge',
    '',
]

skill_files = sorted(glob.glob(os.path.join(repo_dir, 'plugins', '*', 'skills', '*', 'SKILL.md')))

for skill_path in skill_files:
    parts = os.path.normpath(skill_path).split(os.sep)
    domain = parts[parts.index('plugins') + 1]

    # Strip YAML frontmatter (--- ... ---) from SKILL.md body
    content = open(skill_path, encoding='utf-8').read()
    body = re.sub(r'^---\n.*?\n---\n', '', content, count=1, flags=re.DOTALL).strip()

    lines.append(f'### {domain}')
    lines.append('')
    lines.append(body)
    lines.append('')

# Ensure parent directory exists (needed for global ~/.codex/ path)
os.makedirs(os.path.dirname(out_path) or '.', exist_ok=True)

with open(out_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines) + '\n')

print(f'  [OK] {out_path}')
print(f'  ({len(skill_files)} domains inlined)')
PYEOF

fi  # end Codex block
