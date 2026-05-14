#!/usr/bin/env python3
"""
Run 20 bread-recipe URLs through GeekBread's import pipeline and produce a
markdown report comparing imported output vs. the source page.

Pipeline mirrors what the iOS app does in RecipeEditorScreen.importFromURL:

  1. Fetch HTML
  2. Pull schema.org Recipe out of JSON-LD <script> tags
  3. Run the deterministic parser (Python port of RecipeImporter.swift) to
     get an ImportedRecipe draft
  4. Send draft + raw HTML to Claude Haiku with the EXACT system prompt
     from RemoteRecipeAssist.swift
  5. Apply the model's diff (preferments, dropped rows, stage temps/folds/
     kinds, bread type)
  6. Compare against the source ingredients/instructions and record the
     diffs

Output: per-recipe JSON in eval/output/<slug>.json plus a single markdown
report at eval/output/REPORT.md.

Requires:
  - ANTHROPIC_API_KEY in env (sourced from .env.eval by the runner shell).
  - Network access.
  - Python 3.10+ stdlib only — no requests, no anthropic SDK.
"""

import json
import os
import re
import sys
import time
import urllib.request
import urllib.error
import gzip
import io
from html.parser import HTMLParser
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

# ----- Configuration -----

MODEL = "claude-haiku-4-5-20251001"
HAIKU_MAX_TOKENS = 2048
# Anthropic free/low tier caps Haiku at 50K input tokens/min. 60K chars of
# HTML is ~15K tokens — at that size we only get 3 calls/min before 429.
# Truncating to 25K chars (~6K tokens) plus a 20s pacing sleep keeps us
# comfortably under the cap. Mostly we just need section headers and oven
# temps from the HTML; the deterministic ingredient/stage lists are already
# in the user message.
HTML_TRUNCATE_CHARS = 25_000
REQUEST_TIMEOUT = 30
FETCH_RETRIES = 2
HAIKU_RETRIES = 4
PACING_SLEEP_S = 20            # between recipes — stay under 50K tpm
SKIP_EXISTING_OK = True        # rerun only failed/missing slugs

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "output"
OUT.mkdir(exist_ok=True)

# The 20 URLs. Diverse across bread type and preferment style.
RECIPES = [
    # Lean yeasted / sandwich
    ("kingarthur-classic-white-sandwich",
     "https://www.kingarthurbaking.com/recipes/king-arthurs-classic-white-sandwich-bread-recipe"),
    ("kingarthur-pain-de-mie",
     "https://www.kingarthurbaking.com/recipes/pain-de-mie-recipe"),
    # No-knead
    ("simplyrecipes-no-knead",
     "https://www.simplyrecipes.com/recipes/no_knead_bread/"),
    # Sourdough
    ("kingarthur-naturally-leavened",
     "https://www.kingarthurbaking.com/recipes/naturally-leavened-sourdough-bread-recipe"),
    ("perfectloaf-beginners-sourdough",
     "https://www.theperfectloaf.com/beginners-sourdough-bread/"),
    ("perfectloaf-100-whole-wheat-sourdough",
     "https://www.theperfectloaf.com/100-whole-wheat-sourdough/"),
    ("kingarthur-classic-baguettes",
     "https://www.kingarthurbaking.com/recipes/classic-baguettes-recipe"),
    ("foodgeek-ciabatta",
     "https://foodgeek.dk/en/ciabatta-recipe/"),
    ("perfectloaf-best-sourdough",
     "https://www.theperfectloaf.com/best-sourdough-recipe/"),
    # Enriched (tangzhong / yudane / brioche)
    ("perfectloaf-sourdough-shokupan",
     "https://www.theperfectloaf.com/sourdough-shokupan/"),
    ("kingarthur-japanese-milk-bread",
     "https://www.kingarthurbaking.com/recipes/japanese-milk-bread-rolls-recipe"),
    ("kingarthur-brioche",
     "https://www.kingarthurbaking.com/recipes/classic-brioche-recipe"),
    ("sallysbaking-brioche",
     "https://sallysbakingaddiction.com/brioche/"),
    # Rye
    ("kingarthur-sourdough-rye",
     "https://www.kingarthurbaking.com/recipes/jeffreys-sourdough-rye-bread-recipe"),
    ("kingarthur-light-rye",
     "https://www.kingarthurbaking.com/recipes/light-rye-bread-recipe"),
    # Flatbread / focaccia
    ("kingarthur-sourdough-pita",
     "https://www.kingarthurbaking.com/recipes/sourdough-pita-bread-recipe"),
    ("perfectloaf-focaccia",
     "https://www.theperfectloaf.com/a-simple-focaccia/"),
    # Boiled
    ("kingarthur-bagels",
     "https://www.kingarthurbaking.com/recipes/water-bagels-recipe"),
    ("kingarthur-soft-pretzels",
     "https://www.kingarthurbaking.com/recipes/hot-buttered-soft-pretzels-recipe"),
    # Griddle
    ("kingarthur-english-muffins",
     "https://www.kingarthurbaking.com/recipes/english-muffins-recipe"),
]

# ----- HTTP -----

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/17.0 Safari/605.1.15")


def fetch(url: str) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": UA,
            "Accept": "text/html,application/xhtml+xml",
            "Accept-Encoding": "gzip",
            "Accept-Language": "en-US,en;q=0.9",
        },
    )
    last_err: Exception | None = None
    for attempt in range(FETCH_RETRIES + 1):
        try:
            with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as r:
                raw = r.read()
                if r.headers.get("Content-Encoding", "") == "gzip":
                    raw = gzip.decompress(raw)
                charset = r.headers.get_content_charset() or "utf-8"
                return raw.decode(charset, errors="replace")
        except (urllib.error.URLError, TimeoutError) as e:
            last_err = e
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"fetch failed after retries: {last_err}")


# ----- JSON-LD extraction -----

JSON_LD_BLOCK = re.compile(
    r'<script[^>]*type=["\']application/ld\+json["\'][^>]*>(.*?)</script>',
    re.DOTALL | re.IGNORECASE,
)


def extract_jsonld_recipe(html: str) -> dict | None:
    """Find the Recipe object in any JSON-LD script tag. Handles flat,
    @graph-wrapped, and array forms."""
    for m in JSON_LD_BLOCK.finditer(html):
        body = m.group(1).strip()
        # Strip JS comments and CDATA wrappers that occasionally show up
        body = re.sub(r"^/\*.*?\*/", "", body, flags=re.DOTALL).strip()
        body = body.replace("<![CDATA[", "").replace("]]>", "")
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            # Some pages stuff multiple objects newline-separated
            continue
        recipe = find_recipe(data)
        if recipe:
            return recipe
    return None


def find_recipe(node: Any) -> dict | None:
    if isinstance(node, dict):
        types = node.get("@type")
        if isinstance(types, str):
            types_list = [types]
        elif isinstance(types, list):
            types_list = types
        else:
            types_list = []
        if any(t == "Recipe" for t in types_list):
            return node
        if "@graph" in node:
            r = find_recipe(node["@graph"])
            if r:
                return r
        # Some sites nest the recipe under "mainEntity" or similar
        for key in ("mainEntity", "itemListElement", "hasPart"):
            if key in node:
                r = find_recipe(node[key])
                if r:
                    return r
    elif isinstance(node, list):
        for item in node:
            r = find_recipe(item)
            if r:
                return r
    return None


# ----- Plain-text HTML extraction (fallback when JSON-LD missing) -----

class _TextExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self.buf: list[str] = []
        self.skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style", "noscript", "svg"):
            self.skip += 1

    def handle_endtag(self, tag):
        if tag in ("script", "style", "noscript", "svg") and self.skip > 0:
            self.skip -= 1

    def handle_data(self, data):
        if self.skip == 0:
            self.buf.append(data)


def html_to_text(html: str) -> str:
    p = _TextExtractor()
    p.feed(html)
    text = "".join(p.buf)
    # Normalize whitespace
    return re.sub(r"\s+", " ", text).strip()


# ----- Deterministic parser (port of RecipeImporter.swift) -----

# Categories mirror IngredientCategory in Recipe.swift.
CAT_FLOUR = "Flour"
CAT_LIQUID = "Liquid"
CAT_SALT = "Salt"
CAT_LEAVEN = "Leaven"
CAT_FAT = "Fat"
CAT_SWEET = "Sweet"
CAT_INCLUSION = "Inclusion"


def category_guess(name: str) -> str:
    """Mirror of RecipeImporter.swift categoryGuess (after the dry-milk fix)."""
    lower = name.lower()
    if "salt" in lower:
        return CAT_SALT
    if any(k in lower for k in ("starter", "levain", "poolish", "biga", "yeast")):
        return CAT_LEAVEN
    if any(k in lower for k in ("dry milk", "milk powder", "powdered milk",
                                  "nonfat dry", "non-fat dry")):
        return CAT_INCLUSION
    if "water" in lower or "milk" in lower or "egg" in lower or "juice" in lower:
        return CAT_LIQUID
    if "butter" in lower and "melted" in lower:
        return CAT_LIQUID
    if any(k in lower for k in ("sugar", "honey", "syrup", "molasses")):
        return CAT_SWEET
    if any(k in lower for k in ("butter", "oil", "lard", "shortening")):
        return CAT_FAT
    if any(k in lower for k in ("seed", "nut", "raisin", "cheese",
                                  "chocolate", "cinnamon")):
        return CAT_INCLUSION
    return CAT_FLOUR


# Gram extraction. We try (a) leading metric, (b) parenthesized metric.
LEADING_METRIC = re.compile(
    r"^\s*(\d+(?:\.\d+)?|\d+/\d+)\s*(g|grams?|kg|kilogram|kilograms|oz|ounces?)\b\s*(.*)$",
    re.IGNORECASE,
)
PAREN_METRIC = re.compile(r"\(\s*(\d+(?:\.\d+)?)\s*(g|grams?|kg)\b[^)]*\)",
                           re.IGNORECASE)

# Volume + name (for table lookup)
LEADING_VOL = re.compile(
    r"^\s*(\d+(?:\s+\d+/\d+)?(?:[.,]\d+)?|\d+/\d+)\s*"
    r"(cups?|tablespoons?|tbsp\.?|tbs\.?|teaspoons?|tsp\.?)\b\s*(.*)$",
    re.IGNORECASE,
)

# Volume → grams lookup (subset of IngredientWeightTable.swift)
WEIGHT_TABLE: dict[str, dict[str, float]] = {
    # cups (volume — multiply by quantity)
    "all-purpose flour":   {"cup": 120, "tablespoon": 7.5, "teaspoon": 2.5},
    "bread flour":         {"cup": 120, "tablespoon": 7.5, "teaspoon": 2.5},
    "whole wheat flour":   {"cup": 113, "tablespoon": 7,   "teaspoon": 2.3},
    "rye flour":           {"cup": 102, "tablespoon": 6.4, "teaspoon": 2.1},
    "water":               {"cup": 227, "tablespoon": 14,  "teaspoon": 5},
    "milk":                {"cup": 227, "tablespoon": 14,  "teaspoon": 5},
    "dry milk":            {"cup": 113, "tablespoon": 7.1, "teaspoon": 2.4},
    "milk powder":         {"cup": 113, "tablespoon": 7.1, "teaspoon": 2.4},
    "honey":               {"cup": 340, "tablespoon": 21,  "teaspoon": 7},
    "sugar":               {"cup": 198, "tablespoon": 12.4,"teaspoon": 4.2},
    "brown sugar":         {"cup": 213, "tablespoon": 13.3,"teaspoon": 4.4},
    "butter":              {"cup": 227, "tablespoon": 14,  "teaspoon": 5},
    "oil":                 {"cup": 200, "tablespoon": 12.5,"teaspoon": 4.2},
    "salt":                {"cup": 273, "tablespoon": 17,  "teaspoon": 6},
    "yeast":               {"cup": 150, "tablespoon": 9,   "teaspoon": 3},
}

UNICODE_FRAC = {
    "½": " 1/2", "¼": " 1/4", "¾": " 3/4",
    "⅓": " 1/3", "⅔": " 2/3",
    "⅛": " 1/8", "⅜": " 3/8", "⅝": " 5/8", "⅞": " 7/8",
}


def parse_quantity(s: str) -> float | None:
    s = s.strip().replace(",", ".")
    for k, v in UNICODE_FRAC.items():
        s = s.replace(k, v)
    s = s.replace(" and ", " ").strip()
    # Mixed: "2 1/4"
    m = re.match(r"^(\d+)\s+(\d+)/(\d+)$", s)
    if m:
        return float(m.group(1)) + float(m.group(2)) / float(m.group(3))
    # Simple fraction
    m = re.match(r"^(\d+)/(\d+)$", s)
    if m:
        return float(m.group(1)) / float(m.group(2))
    try:
        return float(s)
    except ValueError:
        return None


def normalize_unit(raw: str) -> str | None:
    r = raw.lower().rstrip(".")
    if r in ("cup", "cups"):
        return "cup"
    if r in ("tablespoon", "tablespoons", "tbsp", "tbs"):
        return "tablespoon"
    if r in ("teaspoon", "teaspoons", "tsp"):
        return "teaspoon"
    return None


def table_lookup(name: str, qty: float, unit: str) -> float | None:
    lower = name.lower()
    # Prefer longest keyword that appears
    best: tuple[str, float] | None = None
    for k, units in WEIGHT_TABLE.items():
        if k in lower and unit in units:
            if best is None or len(k) > len(best[0]):
                best = (k, units[unit] * qty)
    return best[1] if best else None


def normalize_grams(qty: float, unit: str) -> float:
    u = unit.lower().rstrip("s").rstrip(".")
    if u in ("g", "gram"):
        return qty
    if u in ("kg", "kilogram"):
        return qty * 1000
    if u in ("oz", "ounce"):
        return qty * 28.3495
    return qty


def clean_name(raw: str) -> str:
    # Strip parenthesized blocks (often the metric annotation)
    s = re.sub(r"\([^)]*\)", " ", raw)
    s = re.sub(r"\s+", " ", s).strip(" ,.;:")
    return s


def parse_egg_count(line: str) -> tuple[float, str] | None:
    """'2 large eggs' → (100g, 'large eggs'). Approx 50g per large egg."""
    m = re.match(r"^\s*(\d+(?:\.\d+)?)\s+(large|medium|small|extra[- ]large|jumbo)?\s*eggs?\b",
                 line, re.IGNORECASE)
    if not m:
        return None
    qty = float(m.group(1))
    size = (m.group(2) or "large").lower()
    per = {"jumbo": 63, "extra large": 56, "extra-large": 56,
           "large": 50, "medium": 44, "small": 38}.get(size, 50)
    return qty * per, f"{size} egg"


def parse_ingredient_line(line: str) -> dict:
    """Return {name, weight_g, category, raw, source}."""
    trimmed = line.strip()
    # 1. Parenthesized grams: "1¼ cups (282g) lukewarm water"
    m = PAREN_METRIC.search(trimmed)
    if m:
        grams = normalize_grams(float(m.group(1)), m.group(2))
        name = clean_name(trimmed)
        return {"name": name, "weight_g": grams,
                "category": category_guess(name), "raw": trimmed,
                "source": "paren-metric"}
    # 2. Leading metric: "500 g bread flour"
    m = LEADING_METRIC.match(trimmed)
    if m:
        qty = parse_quantity(m.group(1)) or 0
        grams = normalize_grams(qty, m.group(2))
        name = m.group(3).strip(" ,.;:")
        name = clean_name(name)
        return {"name": name, "weight_g": grams,
                "category": category_guess(name), "raw": trimmed,
                "source": "leading-metric"}
    # 3. Volume + table lookup: "2 1/4 teaspoons instant yeast"
    m = LEADING_VOL.match(trimmed)
    if m:
        qty = parse_quantity(m.group(1))
        unit = normalize_unit(m.group(2))
        rest = clean_name(m.group(3))
        if qty and unit and rest:
            g = table_lookup(rest, qty, unit)
            if g is not None:
                return {"name": rest, "weight_g": g,
                        "category": category_guess(rest), "raw": trimmed,
                        "source": "table"}
    # 4. Egg count
    egg = parse_egg_count(trimmed)
    if egg:
        return {"name": "egg", "weight_g": egg[0],
                "category": CAT_LIQUID, "raw": trimmed,
                "source": "egg-count"}
    # 5. Fall through
    return {"name": clean_name(trimmed), "weight_g": 0,
            "category": category_guess(trimmed), "raw": trimmed,
            "source": "unparsed"}


# Stage classification (port of stageKindGuess + parseDurationWindow)

STAGE_AUTOLYSE = "Autolyse"
STAGE_FEED = "Feed levain"
STAGE_YUDANE = "Prep yudane"
STAGE_POOLISH = "Prep poolish"
STAGE_TANGZHONG = "Cook tangzhong"
STAGE_ADD_BUTTER = "Add butter"
STAGE_BULK_FOLD = "Bulk + folds"
STAGE_BULK = "Bulk"
STAGE_DIVIDE = "Divide"
STAGE_PRE_SHAPE = "Pre-shape"
STAGE_DIVIDE_SHAPE = "Divide & shape"
STAGE_FINAL_SHAPE = "Final shape"
STAGE_PROOF = "Proof"
STAGE_FINAL_PROOF = "Final proof"
STAGE_COLD_RETARD = "Cold retard"
STAGE_BAKE = "Bake"
STAGE_MIX = "Mix"


def stage_kind_guess(text: str) -> str:
    lower = text.lower()
    if "autolyse" in lower:
        return STAGE_AUTOLYSE
    if "levain" in lower or "feed" in lower:
        return STAGE_FEED
    if "yudane" in lower:
        return STAGE_YUDANE
    if "poolish" in lower:
        return STAGE_POOLISH
    if "tangzhong" in lower:
        return STAGE_TANGZHONG
    if "butter" in lower and "add" in lower:
        return STAGE_ADD_BUTTER
    if "fold" in lower or "stretch" in lower:
        return STAGE_BULK_FOLD
    if "bulk" in lower or "ferment" in lower or "rise" in lower or "rest" in lower:
        return STAGE_BULK
    if "divide" in lower and "shape" in lower:
        return STAGE_DIVIDE_SHAPE
    if "pre-shape" in lower or "preshape" in lower or "pre shape" in lower:
        return STAGE_PRE_SHAPE
    if "shape" in lower or "form" in lower:
        return STAGE_FINAL_SHAPE
    if "retard" in lower or "fridge" in lower or "refrigerator" in lower or "overnight" in lower:
        return STAGE_COLD_RETARD
    if "proof" in lower or "final rise" in lower:
        return STAGE_FINAL_PROOF
    if "bake" in lower or "oven" in lower:
        return STAGE_BAKE
    if "mix" in lower or "combine" in lower or "knead" in lower or "stir" in lower:
        return STAGE_MIX
    return STAGE_MIX


DUR_COMPOUND = re.compile(r"(\d+)\s*(?:hour|hr)s?\s*(?:and\s*)?(\d+)\s*(?:minute|min)s?\b", re.I)
DUR_RANGE = re.compile(r"(\d+(?:\.\d+)?)\s*(?:to|-|–|—)\s*(\d+(?:\.\d+)?)\s*(hour|hr|minute|min)s?\b", re.I)
DUR_SINGLE = re.compile(r"(\d+(?:\.\d+)?)\s*(hour|hr|minute|min)s?\b", re.I)


def parse_duration_min(text: str) -> tuple[int, int | None] | None:
    m = DUR_COMPOUND.search(text)
    if m:
        return int(m.group(1)) * 60 + int(m.group(2)), None
    m = DUR_RANGE.search(text)
    if m:
        lo, hi = float(m.group(1)), float(m.group(2))
        per = 60 if m.group(3).lower().startswith("h") else 1
        return int(round(lo * per)), int(round(hi * per))
    m = DUR_SINGLE.search(text)
    if m:
        val = float(m.group(1))
        per = 60 if m.group(2).lower().startswith("h") else 1
        return int(round(val * per)), None
    if re.search(r"\bovernight\b", text, re.IGNORECASE):
        return 8 * 60, None
    return None


def parse_instructions(raw: Any) -> list[str]:
    out: list[str] = []

    def absorb(v: Any) -> None:
        if isinstance(v, str):
            t = v.strip()
            if t:
                out.append(t)
        elif isinstance(v, dict):
            if "text" in v:
                absorb(v["text"])
            elif "name" in v:
                absorb(v["name"])
            elif "itemListElement" in v:
                absorb(v["itemListElement"])
        elif isinstance(v, list):
            for item in v:
                absorb(item)

    absorb(raw)
    return out


def map_to_draft(recipe: dict, url: str) -> dict:
    """Port of mapToDraft."""
    title = (recipe.get("name") or "").strip() or "Imported recipe"
    ingredients_raw = recipe.get("recipeIngredient") or recipe.get("ingredients") or []
    instructions = parse_instructions(recipe.get("recipeInstructions"))

    ingredients = [parse_ingredient_line(line) for line in ingredients_raw if line.strip()]
    stages = []
    for text in instructions:
        dur = parse_duration_min(text)
        stages.append({
            "kind": stage_kind_guess(text),
            "duration_min": dur[0] if dur else 0,
            "duration_max_min": dur[1] if dur else None,
            "temperature_c": None,
            "note": text,
        })

    total_g = sum(i["weight_g"] for i in ingredients)
    total_flour = sum(i["weight_g"] for i in ingredients if i["category"] == CAT_FLOUR)
    total_liquid = sum(i["weight_g"] for i in ingredients if i["category"] == CAT_LIQUID)
    hydration_pct = (total_liquid / total_flour * 100) if total_flour > 0 else 0

    warnings: list[str] = []
    unparsed = [i for i in ingredients if i["source"] == "unparsed"]
    if unparsed:
        warnings.append(f"{len(unparsed)} ingredient row(s) had no recognizable weight.")
    if not stages:
        warnings.append("No instructions detected.")

    return {
        "title": title,
        "bread_type": "Sourdough",   # importer's hardcoded default
        "hydration_pct": round(hydration_pct, 1),
        "total_dough_g": round(total_g, 1),
        "ingredients": ingredients,
        "stages": stages,
        "preferments": [],
        "warnings": warnings,
        "source_url": url,
    }


# ----- Haiku call (mirrors RemoteRecipeAssist.swift) -----

SYSTEM_PROMPT = """\
You are a bread-recipe normalizer. The user pastes the deterministic
output of a recipe-page importer plus the raw HTML of the source. The
importer misses structural information that the HTML often makes
obvious:
  - Whether the recipe is sourdough / lean yeasted / enriched / rye /
    flatbread / quick bread / steamed.
  - Whether some of the listed "ingredients" actually belong to a
    preferment (Poolish, Levain, Tangzhong, Yudane, Biga). The HTML
    often has section headers like "For the tangzhong:", "Tangzhong
    (optional):", "Make the levain:", "Build the poolish:", "For the
    dough:" that the JSON-LD flattens into one ingredient list.
  - Whether an ingredient line like "100 g ripe sourdough starter" /
    "200 g active starter" / "50 g bubbly 100% hydration starter" is
    itself a levain — it is, and it should become a `levain`
    preferment with that single Leaven-category row moved into it.
  - Whether the bake / proof / autolyse / mix stages have an oven or
    ambient temperature stated in the source.
  - Whether the bulk + folds stage states a specific number of folds.
  - Whether some "ingredients" are actually equipment notes, washes,
    sub-recipes, or directional text that got into the list by
    accident.

Output a SINGLE JSON object matching this schema (omit fields you
don't have evidence for):

{
  "breadType": "Sourdough" | "Lean yeasted" | "Enriched" | "Rye" | "Flatbread" | "Quick bread" | "Steamed" | null,
  "preferments": [
    {
      "id": "levain" | "yudane" | "tangzhong" | "biga" | "poolish",
      "name": "string",
      "technique": "string (one-line technique e.g. '1:5 cook to 65°C')",
      "prep": "string (one or two sentences)",
      "flourPct": <number, % of TOTAL flour represented by this preferment>,
      "ingredients": [
        {
          "name": "string",
          "category": "Flour" | "Liquid" | "Salt" | "Leaven" | "Fat" | "Sweet" | "Inclusion",
          "weightGrams": <number>,
          "bakersPct": <number, % of total flour>
        }
      ]
    }
  ],
  "ingredientIndicesToRemove": [<0-indexed integer>, ...],
  "stageTemperatures": { "<stage-index>": <celsius number> },
  "stageFolds": { "<stage-index>": <integer count> },
  "stageTypes": { "<stage-index>": "Feed levain" | "Prep yudane" | "Prep poolish" | "Cook tangzhong" | "Autolyse" | "Mix" | "Add butter" | "Bulk + folds" | "Bulk" | "Divide" | "Pre-shape" | "Divide & shape" | "Final shape" | "Proof" | "Final proof" | "Cold retard" | "Bake" },
  "notes": ["short human-readable summary of what you changed", ...]
}

Rules — read carefully:
  1. You may only REMOVE or RELABEL existing ingredient rows, or MOVE
     them into a preferment block. You may NOT invent new
     ingredients. Every preferment ingredient name should match (or
     be a close paraphrase of) a name in the input list.
  2. If you create a preferment, every ingredient it contains must
     correspond to a row in the input list — and those rows must
     also appear in `ingredientIndicesToRemove` so the editor
     doesn't double-count flour/water.
  3. **Inline starter is a levain.** If the input ingredient list has
     a row whose name contains "starter" or "levain" with a stated
     gram weight (e.g. "100 g ripe sourdough starter"), emit a
     preferment with `id: "levain"`, technique like "Use ripe
     100% hydration starter", flourPct ≈ (weight ÷ 2) ÷ total flour
     × 100 (assuming 100% hydration unless the source states
     otherwise), one ingredient row {category: "Leaven", name copied
     from input, weightGrams copied from input}, and put that row's
     index in `ingredientIndicesToRemove`. Don't synthesize a
     separate flour+water pair — the editor's math expands it.
  4. **Look for section headers in the raw HTML** like "For the
     tangzhong:", "Tangzhong (optional):", "Make the levain:",
     "Build the poolish:", "For the levain build:", "Yudane:",
     "Biga:". Every ingredient line that appears under such a
     header in the source belongs to that preferment, even when
     the deterministic ingredient list interleaves header lines
     and recipe-body lines without preserving the grouping. Treat
     "(optional)" as still-extract — if the section is on the
     page, populate it; the user will decide whether to use it.
     **Reject sections that LOOK like preferments but aren't**:
     "Water bath:", "Lye bath:", "Boiling water:", "Kettling
     liquid:", "Egg wash:", "Glaze:", "Topping:", "Filling:",
     "For brushing:", "For dusting:", "For the pan:", "Finishing
     salt:". These are equipment / finishing prep, not
     fermentation pre-stages, regardless of how the source titles
     them. The preferment's `id` MUST be one of
     `levain / tangzhong / yudane / biga / poolish` — never emit a
     preferment whose `id` can't be mapped to one of those five.
     A `tangzhong / yudane / biga / poolish` ALWAYS contains at
     least one Flour-category ingredient AND one Liquid-category
     ingredient; if the section's contents don't satisfy that,
     it's not a preferment.
  5. If you are unsure whether a recipe has a preferment, emit no
     preferments rather than guessing. But "the source has a
     visible 'For the X:' header with rows under it" counts as
     certainty, not a guess.
  6. Convert °F to °C when filling `stageTemperatures` (C = (F − 32) × 5/9).
  7. **Every stage where the dough is in the oven gets a
     temperature.** That includes "Bake at 450°F for 20 min", but
     also follow-on stages like "reduce to 400°F and finish 15 min
     uncovered" or "return to oven for 10 min". When a follow-on
     bake stage doesn't restate a temperature, repeat the most
     recent stated bake temperature on it (in °C). The only bake
     stage that may omit a temperature is one where the source
     explicitly says "oven off" or "residual heat".
  8. `stageFolds` only makes sense on a stage whose kind is "Bulk +
     folds". Don't fold-count a "Bulk" or "Proof" stage.
  9. Keep `notes` short and concrete. One bullet per kind of change.
  10. Output ONLY the JSON object. No explanation outside it.
"""


def build_user_prompt(draft: dict, raw_html: str) -> str:
    ing_lines = "\n".join(
        f"{i}. {ing['name']} — {int(round(ing['weight_g']))}g, category={ing['category']}"
        for i, ing in enumerate(draft["ingredients"])
    )
    # No per-note truncation — the iOS Swift caller sends the full note,
    # and that's where bake temps like "preheat to 350°F" live. Truncating
    # to 140 chars (as an earlier version did) makes Haiku invent
    # temperatures because the stated one is no longer in its context.
    stage_lines = "\n".join(
        f"{i}. kind={st['kind']} duration={st['duration_min']}m note={st['note']}"
        for i, st in enumerate(draft["stages"])
    )
    html_clip = raw_html[:HTML_TRUNCATE_CHARS]
    return (
        f"Title: {draft['title']}\n"
        f"Current bread type (likely wrong default): {draft['bread_type']}\n"
        f"Hydration%: {int(round(draft['hydration_pct']))}\n"
        f"Total dough: {int(round(draft['total_dough_g']))} g\n\n"
        f"Ingredients (deterministic parser output):\n{ing_lines}\n\n"
        f"Stages (deterministic parser output):\n{stage_lines}\n\n"
        "Raw HTML around the recipe (look for \"Poolish:\", \"Levain:\",\n"
        "\"For the dough:\", \"Tangzhong:\", \"Yudane:\" section headers, and\n"
        "for oven temperatures in °F or °C):\n"
        "<<<HTML>>>\n"
        f"{html_clip}\n"
        "<<<END HTML>>>\n\n"
        "Return ONLY the JSON object per the schema. No prose, no\n"
        "markdown fence.\n"
    )


def strip_fence(text: str) -> str:
    t = text.strip()
    if t.startswith("```"):
        first_nl = t.find("\n")
        if first_nl != -1:
            t = t[first_nl + 1:]
        last_fence = t.rfind("```")
        if last_fence != -1:
            t = t[:last_fence]
    return t.strip()


def call_haiku(system: str, user: str) -> tuple[dict | None, str | None]:
    """Returns (parsed_json, raw_text). On HTTP/parse error returns (None, raw).
    Retries on 429 honoring retry-after; retries on 5xx with exponential
    backoff; gives up after HAIKU_RETRIES."""
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        return None, "ANTHROPIC_API_KEY missing"
    payload = json.dumps({
        "model": MODEL,
        "max_tokens": HAIKU_MAX_TOKENS,
        "system": system,
        "messages": [{"role": "user", "content": [{"type": "text", "text": user}]}],
    }).encode("utf-8")

    body: str | None = None
    for attempt in range(HAIKU_RETRIES + 1):
        req = urllib.request.Request(
            "https://api.anthropic.com/v1/messages",
            data=payload,
            headers={
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                body = r.read().decode("utf-8")
            break
        except urllib.error.HTTPError as e:
            err_body = e.read().decode("utf-8", "replace")[:400]
            if e.code == 429 and attempt < HAIKU_RETRIES:
                retry_after = e.headers.get("retry-after") or e.headers.get("anthropic-ratelimit-input-tokens-reset")
                wait = 30
                try:
                    if retry_after:
                        wait = max(5, int(float(retry_after)) + 2)
                except ValueError:
                    pass
                print(f"  …429, sleeping {wait}s (attempt {attempt + 1}/{HAIKU_RETRIES})", flush=True)
                time.sleep(wait)
                continue
            if 500 <= e.code < 600 and attempt < HAIKU_RETRIES:
                time.sleep(3 * (attempt + 1))
                continue
            return None, f"HTTP {e.code}: {err_body}"
        except Exception as e:  # noqa: BLE001
            if attempt < HAIKU_RETRIES:
                time.sleep(2 * (attempt + 1))
                continue
            return None, f"request error: {e}"

    if body is None:
        return None, "no response after retries"

    try:
        env = json.loads(body)
    except json.JSONDecodeError:
        return None, body[:400]
    text = ""
    for block in env.get("content", []):
        if block.get("type") == "text":
            text += block.get("text", "")
    stripped = strip_fence(text)
    try:
        return json.loads(stripped), stripped
    except json.JSONDecodeError:
        return None, stripped[:600]


# ----- Apply fix (port of RemoteRecipeAssist.applyFix) -----

BREAD_TYPES = {"Sourdough", "Lean yeasted", "Enriched", "Rye", "Flatbread",
               "Quick bread", "Steamed"}
PREFERMENT_IDS = {"levain", "yudane", "tangzhong", "biga", "poolish"}
STAGE_KINDS = {"Feed levain", "Prep yudane", "Prep poolish", "Cook tangzhong",
               "Autolyse", "Mix", "Add butter", "Bulk + folds", "Bulk",
               "Divide", "Pre-shape", "Divide & shape", "Final shape",
               "Proof", "Final proof", "Cold retard", "Bake"}


def apply_fix(draft: dict, fix: dict) -> tuple[dict, list[str]]:
    out = json.loads(json.dumps(draft))   # deep copy
    notes: list[str] = []

    bt = fix.get("breadType")
    if isinstance(bt, str) and bt in BREAD_TYPES and bt != out["bread_type"]:
        notes.append(f"breadType: {out['bread_type']} → {bt}")
        out["bread_type"] = bt

    # Stage patches — apply before ingredient removals
    temps = fix.get("stageTemperatures") or {}
    for k, c in temps.items():
        try:
            idx = int(k)
            c = float(c)
        except (ValueError, TypeError):
            continue
        if 0 <= idx < len(out["stages"]) and 0 < c < 350:
            out["stages"][idx]["temperature_c"] = c
            notes.append(f"stage {idx} temp ← {round(c)}°C")

    folds = fix.get("stageFolds") or {}
    for k, n in folds.items():
        try:
            idx = int(k)
            n = int(n)
        except (ValueError, TypeError):
            continue
        if 0 <= idx < len(out["stages"]) and out["stages"][idx]["kind"] == "Bulk + folds" and 0 < n <= 10:
            out["stages"][idx]["total_folds"] = n
            notes.append(f"stage {idx} folds ← {n}")

    kinds = fix.get("stageTypes") or {}
    for k, v in kinds.items():
        try:
            idx = int(k)
        except ValueError:
            continue
        if 0 <= idx < len(out["stages"]) and v in STAGE_KINDS and v != out["stages"][idx]["kind"]:
            notes.append(f"stage {idx} kind: {out['stages'][idx]['kind']} → {v}")
            out["stages"][idx]["kind"] = v

    # Preferments
    new_pfs: list[dict] = []
    for light in (fix.get("preferments") or []):
        if light.get("id") not in PREFERMENT_IDS:
            continue
        flour_pct = float(light.get("flourPct", 0))
        if not (0 <= flour_pct <= 100):
            continue
        ingredients = []
        for li in light.get("ingredients", []):
            cat = li.get("category")
            if cat not in {CAT_FLOUR, CAT_LIQUID, CAT_SALT, CAT_LEAVEN, CAT_FAT, CAT_SWEET, CAT_INCLUSION}:
                continue
            ingredients.append({
                "name": li.get("name", ""),
                "category": cat,
                "weight_g": float(li.get("weightGrams") or 0),
                "bakers_pct": float(li.get("bakersPct") or 0),
                "section": light["id"],
            })
        if ingredients:
            new_pfs.append({
                "id": light["id"],
                "name": light.get("name", light["id"].title()),
                "technique": light.get("technique", ""),
                "prep": light.get("prep", ""),
                "flour_pct": flour_pct,
                "ingredients": ingredients,
            })
    if new_pfs:
        out["preferments"] = new_pfs
        notes.append(f"preferments: {', '.join(pf['name'] for pf in new_pfs)}")

    # Ingredient removals (descending index)
    drops = sorted({int(i) for i in (fix.get("ingredientIndicesToRemove") or [])
                    if isinstance(i, int) and 0 <= i < len(out["ingredients"])},
                   reverse=True)
    dropped_names: list[str] = []
    for idx in drops:
        dropped_names.append(out["ingredients"][idx]["name"])
        del out["ingredients"][idx]
    if dropped_names:
        notes.append("dropped: " + "; ".join(dropped_names))

    # Recompute total
    out["total_dough_g"] = round(
        sum(i["weight_g"] for i in out["ingredients"])
        + sum(p_i["weight_g"] for p in out["preferments"] for p_i in p["ingredients"]),
        1,
    )

    # Model's own notes
    for n in (fix.get("notes") or [])[:5]:
        n = (n or "").strip()
        if n:
            notes.append(f"model: {n[:200]}")

    return out, notes


# ----- Compare against source -----

def normalize_source(recipe: dict) -> dict:
    """Pull the canonical ingredient/instruction strings + author + yield."""
    ingredients = recipe.get("recipeIngredient") or recipe.get("ingredients") or []
    instructions = parse_instructions(recipe.get("recipeInstructions"))
    yield_ = recipe.get("recipeYield") or recipe.get("yield") or ""
    if isinstance(yield_, list):
        yield_ = " / ".join(str(y) for y in yield_)
    return {
        "name": (recipe.get("name") or "").strip(),
        "ingredients": [s.strip() for s in ingredients if isinstance(s, str)],
        "instructions": instructions,
        "yield": str(yield_).strip(),
    }


def compare(final: dict, source: dict, raw_html: str) -> dict:
    """Heuristic comparison of import vs source page."""
    diffs: list[str] = []

    # Bread type sniff — look for keywords in the source page text
    source_text = (source["name"] + " ".join(source["instructions"]) +
                   " ".join(source["ingredients"])).lower()
    expected_bt: str | None = None
    if "sourdough" in source_text or "levain" in source_text or "ripe starter" in source_text:
        expected_bt = "Sourdough"
    elif "rye flour" in source_text and source_text.count("rye flour") >= 2:
        expected_bt = "Rye"
    elif "pita" in source_text or "naan" in source_text or "focaccia" in source_text \
            or "tortilla" in source_text or "flatbread" in source_text:
        expected_bt = "Flatbread"
    elif ("brioche" in source_text or "shokupan" in source_text or "milk bread" in source_text
          or "challah" in source_text or "egg" in source_text and "butter" in source_text):
        expected_bt = "Enriched"
    elif "bagel" in source_text or "pretzel" in source_text or "muffin" in source_text \
            or "no-knead" in source_text or "sandwich" in source_text or "baguette" in source_text \
            or "ciabatta" in source_text:
        expected_bt = "Lean yeasted"

    if expected_bt and expected_bt != final["bread_type"]:
        diffs.append(f"bread type: got '{final['bread_type']}', source suggests '{expected_bt}'")

    # Preferment sniff
    pf_keywords = {
        "levain": ["levain", "ripe starter", "sourdough starter"],
        "tangzhong": ["tangzhong"],
        "yudane": ["yudane"],
        "poolish": ["poolish"],
        "biga": ["biga"],
    }
    expected_pfs = set()
    for pf, keys in pf_keywords.items():
        for k in keys:
            if k in source_text:
                expected_pfs.add(pf)
                break
    actual_pfs = {p["id"] for p in final["preferments"]}
    missing = expected_pfs - actual_pfs
    extra = actual_pfs - expected_pfs
    if missing:
        diffs.append(f"missing preferment(s): {sorted(missing)}")
    if extra:
        diffs.append(f"extraneous preferment(s): {sorted(extra)}")

    # Ingredient count mismatch
    src_count = len(source["ingredients"])
    out_count = len(final["ingredients"]) + sum(len(p["ingredients"]) for p in final["preferments"])
    if abs(src_count - out_count) > 1:
        diffs.append(f"ingredient row count: source has {src_count}, import has {out_count}")

    # Unparsed weight rows
    no_weight = [i for i in final["ingredients"] if i["weight_g"] == 0]
    if no_weight:
        diffs.append(f"{len(no_weight)} of {len(final['ingredients'])} main-dough rows missing a weight")

    # Stage temperature coverage
    stages_with_bake = [s for s in final["stages"] if s["kind"] == "Bake"]
    bake_no_temp = [s for s in stages_with_bake if not s.get("temperature_c")]
    if bake_no_temp:
        diffs.append(f"{len(bake_no_temp)} of {len(stages_with_bake)} bake stage(s) have no temperature")

    # Stage count mismatch
    if final["stages"] and len(final["stages"]) != len(source["instructions"]):
        diffs.append(f"stage count: source has {len(source['instructions'])}, import has {len(final['stages'])}")

    # Stages without a duration
    no_dur = [s for s in final["stages"] if s["duration_min"] == 0 and s["kind"] != "Bake"]
    if no_dur:
        diffs.append(f"{len(no_dur)} of {len(final['stages'])} non-bake stage(s) have no duration")

    return {
        "expected_bread_type": expected_bt,
        "diffs": diffs,
        "source_ingredient_count": src_count,
        "import_ingredient_count": out_count,
        "source_stage_count": len(source["instructions"]),
        "import_stage_count": len(final["stages"]),
    }


# ----- Main loop -----

def slugify(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def process(slug: str, url: str) -> dict:
    print(f"[{slug}] fetch", flush=True)
    try:
        html = fetch(url)
    except Exception as e:  # noqa: BLE001
        return {"slug": slug, "url": url, "error": f"fetch: {e}"}
    recipe = extract_jsonld_recipe(html)
    if not recipe:
        return {"slug": slug, "url": url, "error": "no JSON-LD Recipe found"}

    source = normalize_source(recipe)
    draft = map_to_draft(recipe, url)
    user = build_user_prompt(draft, html)
    print(f"[{slug}] haiku call ({len(user)} chars)", flush=True)
    fix, raw = call_haiku(SYSTEM_PROMPT, user)
    if fix is None:
        return {
            "slug": slug, "url": url, "draft": draft, "source": source,
            "error": f"haiku: {raw}",
        }
    final, change_notes = apply_fix(draft, fix)
    cmp = compare(final, source, html)
    return {
        "slug": slug,
        "url": url,
        "draft": draft,
        "fix": fix,
        "final": final,
        "change_notes": change_notes,
        "source": source,
        "comparison": cmp,
    }


def main() -> None:
    results: list[dict] = []
    for slug, url in RECIPES:
        out_path = OUT / f"{slug}.json"
        if SKIP_EXISTING_OK and out_path.exists():
            try:
                prev = json.loads(out_path.read_text())
                if "error" not in prev:
                    print(f"[{slug}] skip — already done", flush=True)
                    results.append(prev)
                    continue
            except json.JSONDecodeError:
                pass
        try:
            r = process(slug, url)
        except Exception as e:  # noqa: BLE001
            r = {"slug": slug, "url": url, "error": f"unexpected: {e}"}
        out_path.write_text(json.dumps(r, indent=2, ensure_ascii=False))
        if "error" in r:
            print(f"[{slug}] ERROR: {r['error']}", flush=True)
        else:
            n_diffs = len(r["comparison"]["diffs"])
            print(f"[{slug}] done — {n_diffs} diffs flagged", flush=True)
        results.append(r)
        time.sleep(PACING_SLEEP_S)

    (OUT / "all-results.json").write_text(json.dumps(results, indent=2, ensure_ascii=False))
    print("\nWrote all-results.json")


if __name__ == "__main__":
    main()
