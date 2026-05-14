#!/usr/bin/env python3
"""
Compare prompt versions side-by-side.

Looks for:
  eval/output/v1/*.json    — original prompt
  eval/output/v2/*.json    — rules 1/2/3 added
  eval/output/*.json       — current (rule 4 tightened) → v3

Produces eval/output/DELTA-REPORT.md with v1→v3 (cumulative) and v2→v3
(rule-4-isolate) scoreboards plus a per-recipe progression table.
"""

import json
from collections import Counter
from datetime import date
from pathlib import Path

OUT = Path(__file__).resolve().parent / "output"
V1 = OUT / "v1"
V2 = OUT / "v2"
V3 = OUT
REPORT = OUT / "DELTA-REPORT.md"


def load(d: Path) -> dict[str, dict]:
    out = {}
    for p in d.glob("*.json"):
        if p.stem in ("all-results",):
            continue
        try:
            j = json.loads(p.read_text())
        except json.JSONDecodeError:
            continue
        out[j.get("slug", p.stem)] = j
    return out


def summarize_counts(results: dict[str, dict]) -> dict:
    bt_correct = 0
    bt_evaluable = 0
    pf_extracted: dict[str, set[str]] = {"levain": set(), "tangzhong": set(),
                                          "yudane": set(), "biga": set(), "poolish": set()}
    diff_freq: Counter = Counter()
    bake_no_temp: set[str] = set()
    no_dur: set[str] = set()
    no_weight: set[str] = set()
    drift: set[str] = set()
    pf_missed: set[str] = set()
    pf_hallucinated: set[str] = set()
    for slug, r in results.items():
        if "error" in r:
            continue
        cmp_ = r.get("comparison", {})
        bt = r.get("final", {}).get("bread_type")
        ebt = cmp_.get("expected_bread_type")
        if ebt:
            bt_evaluable += 1
            if ebt == bt:
                bt_correct += 1
        for p in r.get("final", {}).get("preferments", []):
            pf_extracted.setdefault(p["id"], set()).add(slug)
        for d in cmp_.get("diffs", []):
            if "no temperature" in d:
                bake_no_temp.add(slug)
                diff_freq["bake stage missing temperature"] += 1
            elif "no duration" in d:
                no_dur.add(slug)
                diff_freq["non-bake stage missing duration"] += 1
            elif "missing a weight" in d:
                no_weight.add(slug)
                diff_freq["ingredient row missing a weight"] += 1
            elif "ingredient row count" in d:
                drift.add(slug)
                diff_freq["ingredient count drift"] += 1
            elif "missing preferment" in d:
                pf_missed.add(slug)
                diff_freq["preferment missed"] += 1
            elif "extraneous preferment" in d:
                pf_hallucinated.add(slug)
                diff_freq["preferment hallucinated"] += 1
            elif d.startswith("bread type:"):
                diff_freq["bread type wrong"] += 1
            elif "stage count" in d:
                diff_freq["stage count mismatch"] += 1
            else:
                diff_freq[d[:60]] += 1
    return {
        "bt_correct": bt_correct,
        "bt_evaluable": bt_evaluable,
        "pf_extracted": pf_extracted,
        "diff_freq": dict(diff_freq.most_common()),
        "bake_no_temp": bake_no_temp,
        "no_dur": no_dur,
        "no_weight": no_weight,
        "drift": drift,
        "pf_missed": pf_missed,
        "pf_hallucinated": pf_hallucinated,
    }


LINES: list[str] = []


def w(s: str = "") -> None:
    LINES.append(s)


def scoreboard(label_a: str, label_b: str, sa: dict, sb: dict) -> None:
    w(f"### {label_a} → {label_b}")
    w()
    w(f"| Metric | {label_a} | {label_b} | Δ |")
    w("|---|---:|---:|---:|")
    w(f"| Bread-type accuracy | {sa['bt_correct']}/{sa['bt_evaluable']} | "
      f"{sb['bt_correct']}/{sb['bt_evaluable']} | "
      f"{sb['bt_correct'] - sa['bt_correct']:+d} |")
    w(f"| Bake-temp gap | {len(sa['bake_no_temp'])}/20 | "
      f"{len(sb['bake_no_temp'])}/20 | "
      f"{len(sb['bake_no_temp']) - len(sa['bake_no_temp']):+d} |")
    w(f"| Non-bake duration gap | {len(sa['no_dur'])}/20 | "
      f"{len(sb['no_dur'])}/20 | "
      f"{len(sb['no_dur']) - len(sa['no_dur']):+d} |")
    w(f"| Preferment missed | {len(sa['pf_missed'])}/20 | "
      f"{len(sb['pf_missed'])}/20 | "
      f"{len(sb['pf_missed']) - len(sa['pf_missed']):+d} |")
    w(f"| Preferment hallucinated | {len(sa['pf_hallucinated'])}/20 | "
      f"{len(sb['pf_hallucinated'])}/20 | "
      f"{len(sb['pf_hallucinated']) - len(sa['pf_hallucinated']):+d} |")
    w(f"| Weight-parse gap | {len(sa['no_weight'])}/20 | "
      f"{len(sb['no_weight'])}/20 | "
      f"{len(sb['no_weight']) - len(sa['no_weight']):+d} |")
    w(f"| Ingredient-count drift | {len(sa['drift'])}/20 | "
      f"{len(sb['drift'])}/20 | "
      f"{len(sb['drift']) - len(sa['drift']):+d} |")
    w()
    w(f"**Preferments extracted:**")
    w()
    w(f"| Preferment | {label_a} | {label_b} | Δ |")
    w("|---|---:|---:|---:|")
    for pf in ("levain", "tangzhong", "yudane", "poolish", "biga"):
        a = len(sa["pf_extracted"].get(pf, set()))
        b = len(sb["pf_extracted"].get(pf, set()))
        w(f"| `{pf}` | {a} | {b} | {b - a:+d} |")
    w()


def main() -> None:
    v1 = load(V1)
    v2 = load(V2)
    v3 = load(V3)
    if not v1 or not v2 or not v3:
        print(f"missing one of v1/v2/v3 — counts: v1={len(v1)}, v2={len(v2)}, v3={len(v3)}")
        return

    s1 = summarize_counts(v1)
    s2 = summarize_counts(v2)
    s3 = summarize_counts(v3)
    today = date.today().isoformat()

    w(f"# Prompt evolution v1 → v2 → v3 — {today}")
    w()
    w("**Versions:**")
    w("- **v1** — original prompt shipped before this eval.")
    w("- **v2** — added 3 rules: inline starter as levain, look for HTML "
      "section headers, every oven stage gets a temperature.")
    w("- **v3** — tightened rule 4: reject equipment sections "
      "(Water bath, Lye bath, Egg wash, Glaze, Topping, etc.); require "
      "a preferment to have one Flour + one Liquid ingredient; require "
      "`id` ∈ {levain, tangzhong, yudane, biga, poolish}.")
    w()
    w("All runs use `claude-haiku-4-5-20251001` with HTML truncated to "
      "25K chars and full stage notes (no per-note truncation).")
    w()

    # Headline
    w("## TL;DR")
    w()
    levain_v1 = len(s1["pf_extracted"]["levain"])
    levain_v3 = len(s3["pf_extracted"]["levain"])
    bake_v1 = len(s1["bake_no_temp"])
    bake_v3 = len(s3["bake_no_temp"])
    hall_v2 = len(s2["pf_hallucinated"])
    hall_v3 = len(s3["pf_hallucinated"])

    w(f"**Cumulative v1 → v3:** "
      f"levain extraction {levain_v1} → {levain_v3} ({levain_v3-levain_v1:+d}), "
      f"bake-temp gap {bake_v1} → {bake_v3} ({bake_v3-bake_v1:+d}), "
      f"hallucinated preferments {len(s1['pf_hallucinated'])} → {hall_v3} "
      f"({hall_v3-len(s1['pf_hallucinated']):+d}).")
    w()
    w(f"**Rule-4 tighten (v2 → v3) specifically:** hallucinated preferments "
      f"{hall_v2} → {hall_v3}.")
    diff_v2_pfs = {s: {p['id'] for p in v2[s]['final']['preferments']}
                   for s in v2 if 'final' in v2[s]}
    diff_v3_pfs = {s: {p['id'] for p in v3[s]['final']['preferments']}
                   for s in v3 if 'final' in v3[s]}
    pf_changes = []
    for slug in sorted(set(diff_v2_pfs) | set(diff_v3_pfs)):
        a = diff_v2_pfs.get(slug, set())
        b = diff_v3_pfs.get(slug, set())
        if a != b:
            pf_changes.append((slug, a, b))
    if pf_changes:
        w()
        w("**Preferment-set changes v2 → v3:**")
        w()
        for slug, a, b in pf_changes:
            a_s = ", ".join(sorted(a)) or "(none)"
            b_s = ", ".join(sorted(b)) or "(none)"
            w(f"- `{slug}`: {a_s} → **{b_s}**")
    w()

    # v1 → v3 cumulative scoreboard
    w("## Cumulative scoreboard")
    w()
    scoreboard("v1", "v3", s1, s3)

    # v2 → v3 isolate
    w("## Rule-4 tighten in isolation")
    w()
    scoreboard("v2", "v3", s2, s3)

    # Per-recipe progression
    w("## Per-recipe progression")
    w()
    w("| Recipe | Bread type (v1 → v3) | Preferments (v1 → v3) | Bake gap (v1 → v3) | Diff count (v1 → v3) |")
    w("|---|---|---|---|---|")
    slugs = sorted(set(v1) | set(v2) | set(v3))

    def bt(r: dict) -> str:
        return r.get("final", {}).get("bread_type", "—")

    def pfs(r: dict) -> str:
        ids = sorted(p["id"] for p in r.get("final", {}).get("preferments", []))
        return ", ".join(ids) or "(none)"

    def bake_gap(r: dict) -> str:
        return "gap" if any("no temperature" in d for d in r.get("comparison", {}).get("diffs", [])) else "ok"

    def ndiff(r: dict) -> int:
        return len(r.get("comparison", {}).get("diffs", []))

    for slug in slugs:
        a = v1.get(slug, {})
        b = v2.get(slug, {})
        c = v3.get(slug, {})
        if "error" in a or "error" in b or "error" in c:
            w(f"| `{slug}` | (error) | (error) | (error) | (error) |")
            continue
        bt_cell = f"{bt(a)} → {bt(c)}"
        if bt(a) == bt(c):
            bt_cell = bt(a)
        pf_cell = f"{pfs(a)} → {pfs(c)}"
        if pfs(a) == pfs(c):
            pf_cell = pfs(a)
        bake_cell = f"{bake_gap(a)} → {bake_gap(c)}"
        if bake_gap(a) == bake_gap(c):
            bake_cell = bake_gap(a)
        diff_cell = f"{ndiff(a)} → {ndiff(c)}"
        delta = ndiff(c) - ndiff(a)
        if delta < 0:
            diff_cell += f" (**{delta:+d}**)"
        elif delta > 0:
            diff_cell += f" ({delta:+d})"
        w(f"| `{slug}` | {bt_cell} | {pf_cell} | {bake_cell} | {diff_cell} |")
    w()

    # Detail on the bagels case (the prior hallucination)
    w("## Spot-check: `kingarthur-bagels`")
    w()
    w("This is the recipe that motivated the rule-4 tighten — v2 hallucinated "
      "a `poolish` preferment from its \"Water bath:\" section.")
    w()
    for label, src in [("v1", v1), ("v2", v2), ("v3", v3)]:
        r = src.get("kingarthur-bagels", {})
        if not r or "error" in r:
            continue
        w(f"**{label}:**")
        w()
        w(f"- Bread type: `{r['final']['bread_type']}`")
        pfs_list = r['final'].get('preferments', [])
        if pfs_list:
            for p in pfs_list:
                ing_names = ", ".join(i["name"] for i in p["ingredients"])
                w(f"- Preferment `{p['id']}` ({p.get('name','')}): {ing_names}")
        else:
            w("- Preferments: (none)")
        w(f"- Diffs: " + "; ".join(r["comparison"]["diffs"]) if r["comparison"]["diffs"] else "- Diffs: —")
        w()

    REPORT.write_text("\n".join(LINES) + "\n")
    print(f"Wrote {REPORT} ({len(LINES)} lines)")


if __name__ == "__main__":
    main()
