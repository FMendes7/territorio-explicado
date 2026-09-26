# Decision log

One entry per significant choice: **what** and **why**. Append-only; reversals get a new entry.

## 2026-09-26 — Enter solo, option A, track 3

Solo entry (the 144-hour window is one person's attention → small and deep). Project: an agent that
answers territorial questions in Portugal with evidence from fragmented open geodata. Primary track:
**The Agent That Can Explain Why**; tracks 1 and 2 fit without extra work but are not scored twice.
Rationale: the author's GIS/PostGIS background is the differentiator, the impact story is verifiable,
and all three sponsor layers fit naturally (Zetaris federates PostGIS + REST; Nemotron routes reasoning;
H-MEM gives memory with an audit trail).

## 2026-09-26 — Three pilot regions, not national

CIM Região de Coimbra (19 municipalities), CIM do Cávado (6) and the municipality of Lisbon.
Administrative boundaries (CAOP) national. Why: the hosting server has ~18 GB free with a disk alert at
85 %, and full national COS2023 + hazard + census would blow it; three regions keep the database ≤ 2.5 GB
and cover places the author can validate by hand (Coimbra, Esposende) plus one the jury recognises (Lisbon).

## 2026-09-26 — Nemotron-first

Reasoning via NVIDIA build (OpenAI-compatible): a large Nemotron model plans, a small one extracts and
verifies. Zero cost, complete "token layer" story, cost/latency measured in evals. The client abstracts
the provider so another model can be A/B-tested later. Local inference was ruled out: the only GPU
available has 2 GB.

## 2026-09-26 — Zetaris via Cloud Hobby (BYOC on AWS) + own MCP fallback

Zetaris Hobby is free but runs in the participant's own AWS account; the node is started only during
tests and a budget alert is set. The PostGIS source is exposed to the Zetaris node only (dedicated
container, IP allow-list, TLS, read-only role). If federation cannot push spatial functions down, plan B
is flat views + a precomputed grid-facts table (decision deadline 8 Oct). If Zetaris fails entirely, a
tiny MCP server over the same database keeps the architecture intact (losing only the sponsor points).

## 2026-09-26 — Strict pre-window / window separation

Everything built before 15 Oct is data, accounts, evaluation cases and docs, listed in `PRE-EXISTING.md`.
A private rehearsal prototype exists only to learn; nothing is copied from it. Why: rule 4 ("judged on
new work built during the hackathon"); a clean line is worth more than a head start.

## 2026-09-26 — TypeScript end to end

Node 20 + Express API, MCP TypeScript SDK client, Meterless H-MEM reference (TypeScript, zero deps)
vendored, React + MapLibre UI. Why: fewest moving parts across the sponsor stack; PostGIS does the
spatial work, the app only orchestrates.

## 2026-09-26 — Data platform validated locally before touching the server

The full ETL ran against a throwaway PostGIS container on the laptop (same image as the server,
`postgis/postgis:16-3.4`). Result for the three pilot regions (after dedupe and boundary trim): COS2023 65 683 polygons, fire hazard
124 327 polygons (Cávado 35 818 · Coimbra 87 442 · Lisboa 1 067), INE BGRI 21 482 subsections, CAOP national
3 049 freguesias, APA flood areas 5 polygons; ~570 MB on disk with update bloat, less after dump/restore. Well under the 2.5 GB budget → the server copy will be a
`pg_dump` of schema `open` restored into `territorio-db`, not a re-run of the ETL over the VPN.
All 19 golden cases return facts from every loaded layer (`evals/cases/golden_facts_2026-09-26.txt`,
to be checked by hand); the two "outside" cases behave as designed (Porto: CAOP only; Madrid: nothing).

Decisions taken while loading (each one cost time; see `docs/lessons.md`):
- read big GeoPackages/shapefiles **extracted**, never through `/vsizip/`; build `.qix` first;
- **bbox filter + PostGIS trim** instead of `-clipsrc` (clipping produced GeometryCollections → lost rows);
  features stay whole and get a `region` tag;
- `-nlt CONVERT_TO_LINEAR` because INE stores some MultiSurface geometries;
- fire hazard from the official SNIT zip (WFS broken), `gridcode` 0–5 mapped to labels;
- `facts_at()` casts every value to `text` (RETURN QUERY is strict about varchar vs text);
- dedupe by geometry hash (a feature whose bbox touches two region bboxes is loaded twice) and trim only
  the features that touch the pilot boundary — a naive bbox self-join for dedupe ran 30 min on COS.

## 2026-09-26 — Tier-1 datasets loaded; CRUS (all pilot municipalities) instead of a Lisbon-only PDM layer

Added to the platform before the window (data only): ICNF burned areas 1975–2025, ICNF protected areas (RNAP +
Natura 2000 ZEC/ZPE), DGT CRUS (PDM land-use classes), INE median €/m² (12 months, parish + municipality) and a
dated IPMA fire-risk snapshot. Choices:
- **CRUS instead of "PDM Lisboa — Planta de Qualificação"**: the dados.gov.pt record we had noted was Cascais's
  and Lisbon publishes no open vector PDM we could reach. DGT's CRUS is the same information (classification and
  qualification from each PDM's ordinance plan, DR 15/2015 classes, original designation kept) for **25 of the 26**
  pilot municipalities (Mortágua's WFS fails server-side), from one official source → one table `open.dgt_crus`
  covering all three regions, so "can I build here?" gets a PDM reading almost everywhere, not only in Lisbon.
  Six PDMs are not re-coded to DR 15/2015 (only their original designation; `esquema` says so, no class is
  inferred). The agent still says the PDM regulation and the constraint maps were not consulted (failure mode 12).
- **INE prices joined through BGRI 2021**, not CAOP 2025: parish codes in the price statistics are the 2013 map
  (failure mode 10). Both the parish and the municipality row are returned, labelled by level.
- **IPMA stays live**: the agent reads `api.ipma.pt` at question time; `open.ipma_rcm_snapshot` only keeps dated
  forecasts (today + 2 days per run) as a fallback and as history for evals.
- **ICNF from its own GeoServer WFS**, not from the DGT SRUP copies (the DGT WFS failed for the fire-hazard map).

Result (local DB, 2026-09-26): burned areas 4 917 polygons, protected areas 25, CRUS 20 333, INE prices 166 rows
(26 municipalities + 140 parishes, 55 with a value), IPMA snapshot 78 rows (26 × 3 days); 0 geometry duplicates;
database 691 MB (390 MB when restored from `pg_dump -Fc -n open`, i.e. without update bloat). The server copy will
be that dump — the restore procedure was rehearsed locally with identical row counts in all 17 tables.
