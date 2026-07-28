# Digital Chip Design — Copilot Workspace Instructions

This workspace contains digital ASIC/FPGA chip design work spanning 14 domains:
architecture evaluation, RTL design, functional verification, formal verification,
logic synthesis, DFT, static timing analysis, HLS, physical design, SoC integration,
memory IP design, compiler toolchain, embedded firmware, and FPGA emulation.

## Behaviour for All Domains

- Apply domain-specific QoR metrics before declaring any stage complete.
- Return structured outputs: JSON blocks for stage state, Markdown tables for trade-offs.
- Execute one stage at a time and report **PASS / FAIL / WARN** after each stage.
- Flag ambiguities before proceeding — chip design is safety-critical.
- When a stage loop limit is exceeded, escalate to the user with full state and recommendations.

## Domain-Specific Rules

Per-domain rules, QoR metrics, and stage sequences are loaded from
`.github/instructions/<domain>.instructions.md` based on the files you are working with.
These files are generated from the plugin SKILL.md sources and contain the full
domain knowledge for each chip design stage.
