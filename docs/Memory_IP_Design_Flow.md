# Memory IP Design Flow

Embedded memory IP design — SRAM, register file, and ROM. Covers requirements
capture, macro selection, array architecture, redundancy and repair, view
generation and QA, and integration handoff.

**Plugin:** `chip-design-memory-ip`
**Skill:** `plugins/memory-ip/skills/memory-ip-design/SKILL.md`
**Orchestrator:** `plugins/memory-ip/agents/memory-ip-orchestrator.md`

---

## Architecture Overview

This domain treats the memory as the *product* rather than as a black box. The
rest of the pipeline consumes memories: PD places them, synthesis marks them
`dont_touch`, DFT tests them, SoC qualifies their views, FPGA swaps them for
BRAM. This flow is what produces them.

### Scope boundary

| Not owned here | Owner |
|---|---|
| MBIST insertion, March patterns, MBIST fault coverage, ATPG | `chip-design-dft` |
| Floorplanning, macro placement, power grid over macros | `chip-design-pd` |
| Timing sign-off, multi-corner STA, ECO closure | `chip-design-sta` |
| Address/memory map assignment, bus fabric attachment | `chip-design-soc` |
| Cache hierarchy and DDR controller architecture | `chip-design-architecture` |

The flow **produces the inputs** those domains consume — memory inventory and
repair-register map for DFT, placement constraints for PD, the `.lib` set and
derates for STA, behavioural models for verification.

---

## Shared State Object

Written into `design_state.json` under the `memory_ip` key:

```json
{
  "memory_ip": {
    "instances": [
      { "name": "", "type": "sram | rf | rom", "depth": 0, "width": 0,
        "ports": "1rw | 1r1w | 2rw", "macro": "", "banks": 0 }
    ],
    "total_area_um2": null,
    "views": { "lib": [], "lef": [], "verilog": [], "gds": [] },
    "repair": { "scheme": "row | column | both | none", "spare_rows": 0,
                "spare_cols": 0, "repair_reg_bits": 0, "efuse_map": null },
    "placement_constraints": [
      { "instance": "", "orientation": "", "halo_um": 0, "channel_um": 0, "group": "" }
    ],
    "ecc": { "scheme": "none | parity | secded", "data_bits": null, "check_bits": null },
    "power_modes": [],
    "signoff": false
  }
}
```

---

## Stage Sequence & Loop-Back Logic

```
memory_requirements → macro_selection → array_architecture → redundancy_repair →
view_generation → integration_prep → memory_signoff
```

| Failing stage | Condition | Loops back to | Max |
|---|---|---|---|
| `macro_selection` | no candidate meets access time | `memory_requirements` | 2× |
| `array_architecture` | area > 120% budget | `macro_selection` | 3× |
| `array_architecture` | bandwidth < target | `memory_requirements` | 1× |
| `redundancy_repair` | projected yield < target | `array_architecture` | 2× |
| `view_generation` | view QA errors > 0 | `macro_selection` | 2× |
| `integration_prep` | placement/channel infeasible | `array_architecture` | 2× |
| `memory_signoff` | Vmin margin short | `array_architecture` | 1× |

### Sign-off criteria
- `view_qa_errors: 0`
- `all_corners_characterized: true`
- `redundancy_allocated: true`
- `mbist_ports_exposed: true`

---

## Stage Summaries

Full domain rules, QoR metrics, and output requirements live in the SKILL file.
This is the orientation summary.

| Stage | Purpose | Key output |
|---|---|---|
| `memory_requirements` | Inventory every instance; classify RF/SRAM/ROM; compute bandwidth; decide ECC from FIT target; enumerate power modes | Instance inventory, ECC decision table |
| `macro_selection` | Sweep column mux factor and bank count; compare candidates on **slow-corner** access-time margin, area, leakage | Selected macro per instance + rejection rationale |
| `array_architecture` | Banking vs. true multi-port; port arrangement and collision policy; wrapper spec; ECC wrapper and scrubbing; Vmin/assist | Bank/port architecture, wrapper spec, ECC scheme |
| `redundancy_repair` | Size spares from defect density; choose repair scheme; size repair register; soft vs. hard repair; efuse map | Repair architecture + projected yield |
| `view_generation` | Generate `.lib`/`.lef`/`.db`/`.v`/`.gds`/`.cdl`; QA pin consistency, timing arcs, corner coverage, obstructions | Complete view set + QA report |
| `integration_prep` | Emit constraints for PD, inventory + repair map for DFT, `.lib` + derates for STA, behavioural model for verification | Handoff package |
| `memory_signoff` | Checklist over all of the above | Signed-off memory IP package |

---

## Constraints

**Required at entry (`memory_requirements`):**
- `constraints.clock.clk_mhz` — sets the access-time budget

**Optional (defaults apply):**

| Key | Default | Meaning |
|---|---|---|
| `memory_ip.vmin_margin_mv` | 50 | Minimum Vmin margin |
| `memory_ip.repair_yield_pct_min` | 99 | Projected post-repair yield floor |
| `memory_ip.ecc_required` | false | Force ECC regardless of FIT calculation |
| `memory_ip.max_aspect_ratio` | 4.0 | Macro aspect-ratio ceiling |
| `memory_ip.retention_required` | true | Deep-sleep retention mandatory |

`constraints.dft.mbist_coverage_pct` is read-only here — owned by `chip-design-dft`.

---

## Supported EDA Tools

**Open-source** — OpenRAM (compiler), CACTI (early estimate), sky130/gf180mcu SRAM
macro sets, Magic (macro DRC/LVS), KLayout (GDS QA), OpenSTA (`.lib` sanity).

**Proprietary** — ARM Artisan compilers, Synopsys compilers + SiliconSmart,
Cadence Liberate, Siemens Tessent MBIST/BISR (reference only; insertion is DFT's).

---

## Memory

- Knowledge: `memory/memory-ip/knowledge.md`
- Experiences: `<MEM>/memory-ip/experiences.jsonl`
- `key_metrics`: `memory_instances`, `total_memory_area_um2`,
  `worst_access_time_ns`, `view_qa_errors`, `projected_repair_yield_pct`
