---
name: memory-keeper
description: >
  Distil accumulated experience records (experiences.jsonl) into updated domain knowledge
  summaries (knowledge.md) for any chip-design domain. Run after every 10 orchestrator
  sessions, or on demand when a domain has collected new issue/fix patterns.
version: 1.0.0
author: chuanseng-ng
license: MIT
allowed-tools: Read, Write, Bash
---

# Skill: Memory Keeper

## Invocation

```text
/chip-design-infrastructure:memory-keeper [--domain <name>] [--all] [--min-records <n>] [--init]
```

- `--domain <name>` — distil a single domain (e.g. `synthesis`, `sta`, `pd`)
- `--all` — distil every domain that has an `experiences.jsonl` with enough records
- `--min-records <n>` — minimum record count to proceed (default: 5); skip domains below threshold
- `--init` — resolve and seed the central memory root, migrating any repo-local runtime data
  (runs `memory_root.py --init`); no distillation. Use once after install or to inspect the location.

If neither `--domain` nor `--all` nor `--init` is given, prompt the user to choose.

---

## Memory Root Resolution

Memory does **not** live at a fixed relative `memory/` path. The active root is resolved by
`memory_root.py` (the single source of truth that `distill.py` and `tools/qor_trends.py` import),
in this priority order:

1. an explicit `--memory-root PATH` argument
2. the `$CHIP_DESIGN_MEMORY_ROOT` environment variable
3. the central default `${XDG_DATA_HOME:-$HOME/.local/share}/chip-design-agents/digital/memory`
   (Windows: `%LOCALAPPDATA%\chip-design-agents\digital\memory`)
4. the in-repo `memory/` tree as a seed fallback (used only if the central root is unwritable)

The in-repo `memory/` tree is the version-controlled **seed**: on first resolution each
`<domain>/knowledge.md` is copied into the central root if absent (never overwriting accumulated
data; runtime `experiences.jsonl`/`run_state.md` are never seeded). Orchestrators resolve this same
root at session start and use it as `<MEM>` for every read/write. To print the resolved path:

```bash
python3 plugins/infrastructure/skills/memory-keeper/memory_root.py        # prints the root
python3 plugins/infrastructure/skills/memory-keeper/memory_root.py --init  # seed + migrate + report
```

Per-project scoping (opt-out of the central store): `export CHIP_DESIGN_MEMORY_ROOT="$PWD/memory"`
(or pass `--memory-root ./memory` to the scripts).

---

## Purpose

Orchestrators write one JSON record to `memory/<domain>/experiences.jsonl` after every run.
Over time those records accumulate issue descriptions, applied fixes, metric ranges, and
tool-flag observations. This skill reads that evidence and merges the new learnings into
`memory/<domain>/knowledge.md` — the Tier-2 summary that every orchestrator reads at session
start. Without periodic distillation, knowledge.md drifts stale while the evidence log grows.

---

## Domains

Valid domain names match the subdirectories under `memory/`:

| Domain | JSONL path |
|--------|-----------|
| `architecture` | `memory/architecture/experiences.jsonl` |
| `compiler` | `memory/compiler/experiences.jsonl` |
| `dft` | `memory/dft/experiences.jsonl` |
| `firmware` | `memory/firmware/experiences.jsonl` |
| `formal` | `memory/formal/experiences.jsonl` |
| `fpga` | `memory/fpga/experiences.jsonl` |
| `hls` | `memory/hls/experiences.jsonl` |
| `infrastructure` | `memory/infrastructure/experiences.jsonl` (opt-in; env-keyed) |
| `memory-ip` | `memory/memory-ip/experiences.jsonl` |
| `pd` | `memory/pd/experiences.jsonl` |
| `rtl-design` | `memory/rtl-design/experiences.jsonl` |
| `soc` | `memory/soc/experiences.jsonl` |
| `sta` | `memory/sta/experiences.jsonl` |
| `synthesis` | `memory/synthesis/experiences.jsonl` |
| `verification` | `memory/verification/experiences.jsonl` |

---

## Stage: load_experiences

### Domain Rules

1. Read `memory/<domain>/experiences.jsonl` (one JSON object per line).
2. Count valid records. If count < `--min-records` (default 5), print a skip notice and
   stop — not enough signal to distil.
3. If the file does not exist or is empty, skip with the same notice.
4. Parse every record into an in-memory list. Ignore malformed lines (log a warning).
5. Group records along three axes for the analysis stage:
   - **Issues + fixes**: collect all `issues_encountered` and `fixes_applied` strings
   - **Tool flags**: scan `notes` and `fixes_applied` for explicit flag/command patterns
     (lines containing `-`, `--`, or backtick-quoted commands)
   - **Metric ranges**: for each numeric field in `key_metrics`, collect the list of values
     across all records; compute min, max, median, and the most recent value

### QoR Metrics to Evaluate
- `records_read`: total valid JSONL records parsed (target ≥ min-records threshold)
- `records_skipped`: malformed lines ignored (target: 0)
- `signoff_rate`: fraction of records where `signoff_achieved: true` (informational)

### Output

Structured summary object (in-memory) passed to `distil_knowledge`:
```json
{
  "domain": "<domain>",
  "record_count": "<n>",
  "date_range": ["<oldest ISO-8601>", "<newest ISO-8601>"],
  "signoff_rate": "<fraction>",
  "issue_fix_pairs": [{"issue": "...", "fix": "...", "count": "<n>"}],
  "tool_flag_candidates": ["<flag or command fragment>"],
  "metric_ranges": {
    "<metric_field>": {"min": "x", "max": "y", "median": "z", "latest": "w"}
  },
  "free_notes": ["<note string>"]
}
```

---

## Stage: distil_knowledge

### Domain Rules

1. Read the **existing** `memory/<domain>/knowledge.md` in full.
2. Using the structured summary from `load_experiences`, identify new evidence that is
   **not already captured** in the current knowledge.md:
   - New issue/fix pairs not yet present under **Known Failure Patterns**
   - New successful flags not yet under **Successful Tool Flags**
   - PDK or tool quirks mentioned in notes not yet under **PDK / Tool Quirks**
3. For each new finding, draft a concise bullet following the style of existing entries:
   - Lead with the symptom or scenario in **bold**
   - Follow with the cause and the fix in plain prose
   - Keep each entry to 2–4 sentences maximum
4. Merge new entries **below** existing entries in the relevant section — never delete or
   overwrite an existing entry unless it directly contradicts new evidence (note the
   contradiction explicitly).
5. If the signoff rate across records is < 50%, add a note in the **Notes** section
   flagging common failure modes that did not reach signoff.
6. Update the `## Notes` section with a distillation timestamp:
   `_Last distilled: <ISO-8601 date> from <n> experience records._`
   Replace any previous such line.
7. Write the updated content back to `memory/<domain>/knowledge.md`.

### Merge Policy

| Scenario | Action |
|----------|--------|
| New issue/fix not in knowledge.md | Add under Known Failure Patterns |
| Existing entry confirmed by ≥ 3 records | Add `(confirmed across N runs)` annotation |
| Existing entry contradicted by ≥ 3 records | Strike through old text, add corrected entry |
| New tool flag observed in ≥ 2 records | Add under Successful Tool Flags |
| Single-record observation | Add only if `signoff_achieved: true` and notes are detailed |

### QoR Metrics to Evaluate
- `new_failure_patterns`: new entries added under Known Failure Patterns (target ≥ 1 if new issues exist)
- `new_tool_flags`: new entries added under Successful Tool Flags (target ≥ 1 if new flags observed)
- `existing_entries_annotated`: count of existing entries updated with confirmation or correction notes
- `contradictions_flagged`: entries where new evidence contradicts old — must never be silently overwritten

### Output Required

- Updated `memory/<domain>/knowledge.md`
- Console summary: how many new entries were added per section, and how many existing
  entries were annotated or corrected

### Optional: claude-mem index
After writing `knowledge.md`, if `mcp__plugin_ecc_memory__add_observations` is available
in this session, emit each new issue/fix pair as an observation to entity
`chip-design-<domain>-fixes`. Skip this step silently if the tool is absent — `knowledge.md`
and `experiences.jsonl` are the canonical records. Do not hard-depend on claude-mem
availability.

---

## Stage: report

### Domain Rules

1. Print a per-domain distillation report:
   ```text
   Domain:        <domain>
   Records read:  <n>
   Date range:    <oldest> → <newest>
   Signoff rate:  <pct>%
   New entries:   +<k> Known Failure Patterns, +<j> Successful Tool Flags, +<i> PDK Quirks
   Annotations:   <m> existing entries updated
   knowledge.md:  memory/<domain>/knowledge.md  [updated]
   ```
2. If `--all` was used, print a summary table across all processed domains.
3. If any domain was skipped (too few records), list them with their current record count.

### QoR Metrics to Evaluate
- `domains_processed`: count of domains where knowledge.md was updated (target ≥ 1)
- `domains_skipped`: count of domains below the min-records threshold (informational)

### Output Required
- Printed per-domain distillation report
- If `--all`: printed summary table across all processed and skipped domains

---

## Sign-off Checklist

- [ ] `experiences.jsonl` read; record count ≥ min-records threshold
- [ ] Structured summary produced (issue/fix pairs, metric ranges, tool flags)
- [ ] Existing `knowledge.md` read without modification during analysis
- [ ] New entries drafted in the style of existing entries
- [ ] Contradicted entries flagged, not silently overwritten
- [ ] Distillation timestamp updated in Notes section
- [ ] `knowledge.md` written back to disk
- [ ] Console report printed

---

## Example Invocations

```bash
# Distil synthesis domain (must have ≥ 5 records)
/chip-design-infrastructure:memory-keeper --domain synthesis

# Distil all domains with ≥ 10 records
/chip-design-infrastructure:memory-keeper --all --min-records 10

# Force distillation even with 3 records (debugging or early feedback)
/chip-design-infrastructure:memory-keeper --domain sta --min-records 3
```
