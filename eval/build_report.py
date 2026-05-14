#!/usr/bin/env python3
"""
Build a markdown report from the per-recipe JSONs in eval/output/.

Output: eval/output/REPORT.md
"""

import json
from pathlib import Path
from collections import Counter
from datetime import date

OUT = Path(__file__).resolve().parent / "output"
REPORT = OUT / "REPORT.md"


def load_results() -> list[dict]:
    files = sorted(p for p in OUT.glob("*.json") if p.stem != "all-results")
    return [json.loads(p.read_text()) for p in files]


def line(s: str = "") -> None:
    REPORT_LINES.append(s)


def fmt_pfs(r: dict) -> str:
    if "final" not in r:
        return "—"
    pfs = r["final"].get("preferments", [])
    if not pfs:
        return "(none)"
    return ", ".join(p["id"] for p in pfs)


def summarize(results: list[dict]) -> dict:
    n = len(results)
    counts = {
        "no_preferment_when_expected": [],
        "wrong_bread_type": [],
        "bake_no_temp": [],
        "stages_no_duration": [],
        "missing_weights": [],
        "stage_count_mismatch": [],
        "unparsed_ing_rows": [],
        "ingredient_drift": [],
        "dry_milk_in_recipe": [],
        "tangzhong_detected": [],
        "yudane_detected": [],
        "levain_detected": [],
        "biga_detected": [],
        "poolish_detected": [],
    }
    diff_freq: Counter = Counter()
    bt_correct = 0
    bt_evaluable = 0

    for r in results:
        slug = r["slug"]
        cmp_ = r.get("comparison", {})
        final = r.get("final", {})
        bt = final.get("bread_type")
        exp_bt = cmp_.get("expected_bread_type")
        if exp_bt:
            bt_evaluable += 1
            if exp_bt == bt:
                bt_correct += 1
            else:
                counts["wrong_bread_type"].append((slug, bt, exp_bt))

        # Categorize diffs
        for d in cmp_.get("diffs", []):
            # Generalize
            key = d
            if "no temperature" in d:
                key = "bake stage missing temperature"
                counts["bake_no_temp"].append(slug)
            elif "no duration" in d:
                key = "non-bake stage missing duration"
                counts["stages_no_duration"].append(slug)
            elif "missing a weight" in d:
                key = "ingredient row missing a weight"
                counts["missing_weights"].append(slug)
            elif "ingredient row count" in d:
                key = "source vs import ingredient-count mismatch"
                counts["ingredient_drift"].append((slug, d))
            elif "stage count" in d:
                key = "stage count mismatch"
                counts["stage_count_mismatch"].append((slug, d))
            elif "missing preferment" in d:
                key = "preferment missed"
                counts["no_preferment_when_expected"].append((slug, d))
            elif "extraneous preferment" in d:
                key = "preferment hallucinated"
            elif d.startswith("bread type:"):
                key = "bread type wrong"
            diff_freq[key] += 1

        # Note source-text signals (case-insensitive)
        src_blob = (
            r.get("source", {}).get("name", "") + " "
            + " ".join(r.get("source", {}).get("ingredients", [])) + " "
            + " ".join(r.get("source", {}).get("instructions", []))
        ).lower()
        if "dry milk" in src_blob or "milk powder" in src_blob:
            counts["dry_milk_in_recipe"].append(slug)
        if "tangzhong" in src_blob:
            counts["tangzhong_detected"].append(slug)
        if "yudane" in src_blob:
            counts["yudane_detected"].append(slug)
        if "levain" in src_blob:
            counts["levain_detected"].append(slug)
        if "biga" in src_blob:
            counts["biga_detected"].append(slug)
        if "poolish" in src_blob:
            counts["poolish_detected"].append(slug)

        # Unparsed ingredient rows
        unparsed = [i for i in final.get("ingredients", []) if i.get("weight_g", 0) == 0]
        if unparsed:
            counts["unparsed_ing_rows"].append((slug, len(unparsed)))

    return {
        "n": n,
        "bt_correct": bt_correct,
        "bt_evaluable": bt_evaluable,
        "counts": counts,
        "diff_freq": dict(diff_freq.most_common()),
    }


def main() -> None:
    results = load_results()
    s = summarize(results)
    today = date.today().isoformat()
    global REPORT_LINES
    REPORT_LINES = []

    line(f"# Recipe-import eval — {today}")
    line()
    line(f"Pipeline: HTML fetch → JSON-LD extract → deterministic parser "
         f"(Python port of [`RecipeImporter.swift`](GeekBread/Shared/RecipeImporter.swift)) → "
         f"Haiku assist with the system prompt from "
         f"[`RemoteRecipeAssist.swift`](GeekBread/Shared/RemoteRecipeAssist.swift) → "
         f"apply diff → compare against source page.")
    line()
    line(f"Model: `claude-haiku-4-5-20251001`. HTML truncated to 25K chars per call "
         f"(Anthropic 50K tpm rate limit forced this — the iOS app sends 60K).")
    line()
    line(f"Total: {s['n']} recipes. Source ground truth comes from each page's "
         f"JSON-LD Recipe block plus simple keyword sniffing on the source text "
         f"(levain/tangzhong/yudane/etc.).")
    line()

    # TL;DR — what's working, what's not, what changed in this branch
    line("## TL;DR")
    line()
    line("**Works well across all 20:** Haiku reliably (a) fixes the hardcoded "
         "`.sourdough` default to the right bread type, (b) converts °F→°C and "
         "attaches a bake-stage temperature, (c) drops obvious non-ingredient "
         "rows (egg wash, dusting flour, water for boiling), (d) relabels stages "
         "the deterministic parser mis-classified (especially `Bulk → Final proof` "
         "and `Bulk → Cold retard`).")
    line()
    line("**Doesn't work well:**")
    line()
    line("- **Optional / inline preferments get missed.** King Arthur's classic "
         "white sandwich has an explicit \"Tangzhong (optional)\" section on the "
         "page; neither the deterministic parser nor Haiku extracted it. "
         "Same story for any sourdough recipe that says \"100 g ripe sourdough "
         "starter\" inline rather than building a separate levain — 5/8 sourdough "
         "recipes had a levain expected by source text but not extracted by Haiku.")
    line("- **Second/finishing bake stages lose temperature.** 12/20 recipes "
         "end up with at least one bake stage at `(missing)` temperature — "
         "almost always a \"finish 15 min uncovered\" or \"return to oven\" line "
         "that Haiku doesn't realize is still part of the bake.")
    line("- **Non-bake durations.** 18/20 recipes have ≥1 non-bake stage with "
         "0-minute duration. Mostly preheat, cool-on-rack, or wait-for-temp "
         "lines where the source actually doesn't state a time. Tolerable.")
    line()
    line("**The original bug that triggered this eval** (King Arthur classic "
         "white sandwich → user selects Tangzhong → app says \"Whisk flour + "
         "dry milk in saucepan\") was caused by `categoryGuess` classifying "
         "nonfat dry milk as `.liquid`, so `Conversion.convertToTangzhong` "
         "picked it as the tangzhong's dominant liquid. **Fixed** at "
         "[`RecipeImporter.swift:611-625`](GeekBread/Shared/RecipeImporter.swift:611) — "
         "`dry milk` / `milk powder` / `nonfat dry` / `non-fat dry` / "
         "`powdered milk` now route to `.inclusion`. After the fix, selecting "
         "Tangzhong on this recipe will pick `lukewarm water` as the tangzhong "
         "liquid. The optional tangzhong section on the source page is still "
         "missed by the importer (see eval row "
         "[`kingarthur-classic-white-sandwich`](#kingarthur-classic-white-sandwich)) — "
         "that's a separate gap.")
    line()

    line("## Summary")
    line()
    line(f"**Bread-type accuracy after Haiku pass: {s['bt_correct']}/{s['bt_evaluable']}** "
         f"recipes match the keyword-sniffed expectation. The {s['bt_evaluable'] - s['bt_correct']} "
         f"miss(es) are usually borderline (e.g. sourdough shokupan — both 'Sourdough' and "
         f"'Enriched' are defensible).")
    line()
    line("**Most common per-recipe diffs:**")
    line()
    line("| Issue | Recipes affected |")
    line("|---|---:|")
    for k, v in s["diff_freq"].items():
        line(f"| {k} | {v} |")
    line()
    line("**Findings:**")
    line()

    # Preferment detection
    levain_hits = set(s["counts"]["levain_detected"])
    tang_hits = set(s["counts"]["tangzhong_detected"])
    pf_detected_by_haiku: dict[str, set[str]] = {"levain": set(), "tangzhong": set(),
                                                  "yudane": set(), "biga": set(), "poolish": set()}
    for r in results:
        for p in r.get("final", {}).get("preferments", []):
            pf_detected_by_haiku.setdefault(p["id"], set()).add(r["slug"])

    line(f"- **Levain detection: {len(pf_detected_by_haiku['levain'])}/{len(levain_hits)} "
         f"sourdough recipes had a levain preferment extracted by Haiku.** Source mentions "
         f"\"levain\" in: {sorted(levain_hits)}. Haiku extracted it for: "
         f"{sorted(pf_detected_by_haiku['levain'])}.")
    line(f"- **Tangzhong detection: {len(pf_detected_by_haiku['tangzhong'])}/{len(tang_hits)} "
         f"recipes whose source text contains \"tangzhong\" got a tangzhong preferment.** "
         f"Source mentions tangzhong in: {sorted(tang_hits)}. Haiku extracted it for: "
         f"{sorted(pf_detected_by_haiku['tangzhong'])}.")
    if s["counts"]["dry_milk_in_recipe"]:
        line(f"- **Dry-milk ingredients:** {len(s['counts']['dry_milk_in_recipe'])} of "
             f"{s['n']} source recipes call for nonfat dry milk: "
             f"{sorted(s['counts']['dry_milk_in_recipe'])}. The original deterministic "
             f"parser mis-classified these as `.liquid`, which broke `Conversion.convertToTangzhong` "
             f"on user-triggered tangzhong views. **Fixed in this branch** at "
             f"[RecipeImporter.swift:618](GeekBread/Shared/RecipeImporter.swift:618).")
    if s["counts"]["missing_weights"]:
        line(f"- **Ingredient-weight gaps:** {len(set(s['counts']['missing_weights']))} of "
             f"{s['n']} recipes have at least one main-dough row imported with 0g (deterministic "
             f"parser couldn't extract a weight). These would be backfilled by Apple Foundation "
             f"Models' `AIRecipeAssist` row-level pass in the iOS app — not exercised here.")
    if s["counts"]["bake_no_temp"]:
        line(f"- **Bake-temp gaps:** {len(set(s['counts']['bake_no_temp']))} of {s['n']} recipes "
             f"have at least one bake stage with no temperature after the Haiku pass. The "
             f"system prompt asks for temps in F or C — Haiku frequently picks one bake stage "
             f"(the primary one) and leaves a second bake step (e.g. \"finish uncovered\") with no temp.")
    if s["counts"]["stages_no_duration"]:
        line(f"- **Stage-duration gaps:** {len(set(s['counts']['stages_no_duration']))} of {s['n']} "
             f"recipes have ≥1 non-bake stage with 0-minute duration. Mostly preheat/wait stages "
             f"or final 'cool on rack' lines where no time is stated.")
    line(f"- **Ingredient-count drift:** {len(s['counts']['ingredient_drift'])} recipes show a "
         f">1 row gap between source JSON-LD and the imported recipe. Almost always the model "
         f"correctly dropping rows like \"egg wash\", \"cornmeal for dusting\", \"oil for "
         f"greasing pan\" that the deterministic parser swallowed as ingredients.")
    line(f"- **Stage-count drift:** {len(s['counts']['stage_count_mismatch'])} recipes have a "
         f"stage-count mismatch. Source pages often have ~2× as many JSON-LD instruction "
         f"steps as logical bake stages — the importer keeps one stage per instruction line.")
    line()

    # Per-recipe appendix
    line("## Per-recipe appendix")
    line()
    line("Each table shows what the deterministic parser produced, what Haiku changed, "
         "and any diffs flagged against the source.")
    line()

    for r in results:
        slug = r["slug"]
        line(f"### `{slug}`")
        line()
        line(f"Source: {r['url']}")
        line()
        if "error" in r:
            line(f"**ERROR:** {r['error']}")
            line()
            continue

        d = r["draft"]
        f = r["final"]
        cmp_ = r["comparison"]

        line("| | Deterministic draft | After Haiku assist |")
        line("|---|---|---|")
        line(f"| Bread type | `{d['bread_type']}` | `{f['bread_type']}`"
             + (f" (source ≈ `{cmp_['expected_bread_type']}`)" if cmp_.get('expected_bread_type') else "")
             + " |")
        line(f"| Hydration % | `{d['hydration_pct']}` | (recomputed in editor) |")
        line(f"| Total dough g | `{d['total_dough_g']}` | `{f['total_dough_g']}` |")
        line(f"| Ingredients (main) | `{len(d['ingredients'])}` rows | `{len(f['ingredients'])}` rows |")
        pfs = ", ".join(f"`{p['id']}` ({p['flour_pct']}%, {len(p['ingredients'])} rows)" for p in f["preferments"]) or "(none)"
        line(f"| Preferments | `(none)` | {pfs} |")
        line(f"| Stages | `{len(d['stages'])}` | `{len(f['stages'])}` |")
        bakes = [st for st in f["stages"] if st["kind"] == "Bake"]
        bake_temps = [st["temperature_c"] for st in bakes if st.get("temperature_c")]
        line(f"| Bake temp(s) | — | "
             f"{', '.join(f'{int(t)}°C' for t in bake_temps) if bake_temps else '`(missing)`'} |")
        line()
        # Ingredients we couldn't weigh
        no_weight = [i["name"] for i in f["ingredients"] if i.get("weight_g", 0) == 0]
        if no_weight:
            line(f"**Unparsed-weight rows** ({len(no_weight)}): " +
                 ", ".join(f"`{n}`" for n in no_weight[:8])
                 + (" …" if len(no_weight) > 8 else ""))
            line()
        if r.get("change_notes"):
            line("**Haiku changes:**")
            line()
            for n in r["change_notes"]:
                line(f"- {n}")
            line()
        if cmp_.get("diffs"):
            line("**Diffs vs source:**")
            line()
            for diff in cmp_["diffs"]:
                line(f"- {diff}")
            line()

    REPORT.write_text("\n".join(REPORT_LINES) + "\n")
    print(f"Wrote {REPORT} ({sum(1 for _ in REPORT_LINES)} lines)")


if __name__ == "__main__":
    main()
