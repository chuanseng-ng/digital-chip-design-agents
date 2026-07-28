"""Unit tests for the memory-keeper distill.py helper."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

DISTILL = Path(__file__).resolve().parents[1] / \
    "plugins/infrastructure/skills/memory-keeper/distill.py"


def test_every_valid_domain_has_metric_fields(distill):
    # The 14 design domains + infrastructure must each be registered.
    assert len(distill.VALID_DOMAINS) == 15
    for dom in distill.VALID_DOMAINS:
        assert dom in distill.METRIC_FIELDS, f"{dom} missing from METRIC_FIELDS"
    assert "infrastructure" in distill.VALID_DOMAINS
    assert "synthesis" in distill.VALID_DOMAINS


def test_load_records_skips_malformed_and_non_objects(distill, tmp_path):
    p = tmp_path / "experiences.jsonl"
    p.write_text(
        '{"a": 1}\n'
        "\n"                       # blank line ignored
        "not json\n"               # malformed -> skipped
        "[1, 2, 3]\n"              # valid JSON but not an object -> skipped
        '{"b": 2}\n')
    records = distill.load_records(p)
    assert records == [{"a": 1}, {"b": 2}]


def test_load_records_missing_file_returns_empty(distill, tmp_path):
    assert distill.load_records(tmp_path / "nope.jsonl") == []


def test_compute_metric_ranges(distill):
    records = [
        {"key_metrics": {"wns_ns": -0.4, "cells": 1000}},
        {"key_metrics": {"wns_ns": -0.2, "cells": 1100}},
        {"key_metrics": {"wns_ns": 0.1}},
    ]
    ranges = distill.compute_metric_ranges(records, "synthesis")
    assert ranges["wns_ns"]["min"] == -0.4
    assert ranges["wns_ns"]["max"] == 0.1
    assert ranges["wns_ns"]["latest"] == 0.1
    assert ranges["wns_ns"]["count"] == 3
    assert ranges["cells"]["count"] == 2


def test_extract_issue_fix_pairs(distill):
    records = [
        {"issues_encountered": ["wns -0.4ns"], "fixes_applied": ["upsize drivers"]},
        {"issues_encountered": ["wns -0.4ns"], "fixes_applied": ["upsize drivers"]},
        {"issues_encountered": ["high area"], "fixes_applied": ["remap"]},
    ]
    pairs = distill.extract_issue_fix_pairs(records)
    top = pairs[0]
    assert top["issue"] == "wns -0.4ns" and top["fix"] == "upsize drivers"
    assert top["count"] == 2


def test_extract_tool_flag_candidates(distill):
    records = [
        {"fixes_applied": ["re-ran synth with -flatten"], "notes": "used `abc -dff` pass"},
    ]
    cands = distill.extract_tool_flag_candidates(records)
    assert "-flatten" in cands
    assert "abc -dff" in cands


def _run(domain, memory_root, min_records=5):
    return subprocess.run(
        [sys.executable, str(DISTILL), domain,
         "--memory-root", str(memory_root), "--min-records", str(min_records)],
        capture_output=True, text=True)


def test_main_skips_below_threshold(tmp_path):
    mem = tmp_path / "memory" / "synthesis"
    mem.mkdir(parents=True)
    (mem / "experiences.jsonl").write_text('{"timestamp": "t", "key_metrics": {}}\n')
    res = _run("synthesis", tmp_path / "memory", min_records=5)
    assert res.returncode == 2
    payload = json.loads(res.stdout)
    assert payload["skipped"] is True
    assert payload["record_count"] == 1


def test_main_emits_summary_when_enough_records(tmp_path):
    mem = tmp_path / "memory" / "synthesis"
    mem.mkdir(parents=True)
    lines = []
    for i in range(5):
        lines.append(json.dumps({
            "timestamp": f"2026-03-0{i+1}T00:00:00Z",
            "key_metrics": {"wns_ns": -0.5 + i * 0.1},
            "issues_encountered": ["x"], "fixes_applied": ["y"],
            "notes": f"run {i}", "signoff_achieved": i % 2 == 0,
        }))
    (mem / "experiences.jsonl").write_text("\n".join(lines) + "\n")
    res = _run("synthesis", tmp_path / "memory", min_records=5)
    assert res.returncode == 0, res.stderr
    payload = json.loads(res.stdout)
    assert payload["skipped"] is False
    assert payload["record_count"] == 5
    assert "wns_ns" in payload["metric_ranges"]
    assert payload["signoff_rate"] == round(3 / 5, 3)


def test_main_rejects_unknown_domain(tmp_path):
    res = _run("not-a-domain", tmp_path / "memory")
    assert res.returncode == 2          # argparse choices error
    assert "invalid choice" in res.stderr
