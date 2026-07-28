# Memory IP Design Domain Knowledge

## Known Failure Patterns

- **Pin-name drift between `.lib`, `.lef`, and `.v`**: Compiler-generated views can disagree on
  pin naming (e.g. `CLK` vs `clk`, `WEN` vs `WEB`) when the wrapper is hand-edited after
  generation. Nothing errors at generation time — the mismatch surfaces as an unconnected port
  at PD or an LEC mismatch much later. Always diff the pin lists across all three views before
  declaring `view_generation` clean.
- **Typical-corner macro selection**: Selecting a macro on typical-corner access time leaves no
  margin at the slow corner, where the sense-amp path degrades disproportionately compared to
  logic. A macro that passes at typical and fails at SS is the most common cause of a late
  loop-back from STA. Always select on slow-corner margin.
- **Permissive behavioural model hides collision bugs**: If the `.v` behavioural model returns
  old data on a write-during-read collision while the real macro returns X, the testbench passes
  and silicon fails. The behavioural model must propagate X for exactly the collision cases the
  macro does not define.
- **ECC treated as a substitute for redundancy**: ECC corrects soft errors; redundancy replaces
  hard defects found at test. Counting ECC toward the post-repair yield target overstates yield
  and is discovered only at wafer sort. Keep the two calculations separate.

## Successful Tool Flags

- `cacti -infile cache.cfg` with `-cache_size`, `-block_size`, `-associativity` — use for the
  first-pass area/power estimate at `memory_requirements` before committing to a compiler run;
  treat its output as an uncertainty band, not a point value.
- `sta -exit lib_check.tcl` running `read_liberty <macro>.lib` per corner — catches missing
  timing arcs and malformed Liberty far faster than waiting for a full STA run.
- `klayout -b -r gds_qa.py -rd gds=<macro>.gds` — batch GDS QA for boundary and obstruction-layer
  checks; scriptable per-instance across the whole inventory.
- `magic -dnull -noconsole -rcfile <pdk>.magicrc` with `drc check` / `extract` — macro-level
  DRC/LVS for OpenRAM-generated layout. Skip for vendor pre-hardened macros.

## PDK / Tool Quirks

- **OpenRAM vs vendor compilers**: OpenRAM generates a complete view set but supports a narrower
  configuration space (limited mux factors and port arrangements). Check that the target
  configuration is generatable before treating it as a candidate — an ungeneratable config that
  looks good on paper wastes a full selection round.
- **sky130 pre-hardened SRAM macros**: The sky130 macro set offers fixed depth/width combinations
  only. Requirements that fall between the available sizes must round up, so capture the resulting
  area over-provisioning explicitly at `macro_selection` rather than discovering it at `pd`.

## Notes

- Record the rejection rationale for every losing macro candidate. Re-spins revisit the same
  trade space, and the reason a candidate lost (aspect ratio, slow-corner margin, leakage) is the
  highest-value thing to carry forward.
- Repair-register width is a hard handoff number to DFT's `bist_insertion`. Changing the spare
  row/column count after DFT has built the BISR chain forces a DFT loop-back — freeze it at
  `redundancy_repair`.
