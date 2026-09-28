# UX specification — Território Explicado

Pre-window design document (text only; no UI code exists in this repository before 15 Oct 2026). The window's web app
is built from this spec. A private throwaway prototype of the same layout is used to test it before the window
(`PRE-EXISTING.md`, rehearsal) — nothing from it is copied here.

Decided 2026-09-28 with Fernando: **Google Maps-like layout** (side panel with cards, clean map, bottom sheet on the
phone), **desktop first** with a good phone experience, **PT-PT by default with an EN toggle**.

## 1. Who uses it and what they need

| User | Arrives with | Leaves with |
|---|---|---|
| A person about to buy or use a plot | an address, a place name, or a plot they can draw | what conditions the plot for what they want to do, with the source of every statement and what is *not* known |
| A judge (5 minutes, no briefing) | the URL | understands the product in 30 s, can run a query in 60 s, can click from a sentence to its dataset, SQL and law |
| A municipal technician | a parcel | the legal layers (PDM, REN, RAN, protected areas) with the diploma, and where the data is missing |

## 2. Principles

1. **Answer first, evidence one click away.** The panel opens with a short summary; details are cards; provenance is a
   drawer. Nothing technical is shown before it is asked for.
2. **Unknown is never free.** A layer that is not published for that municipality is grey, "not available — not
   consulted" — never green, never "outside".
3. **Every value has a source chip** (entity · date) that opens the provenance (dataset, licence, reference date,
   retrieval date, SQL, diploma PDF when there is one).
4. **The map shows what the text says.** Selecting a card highlights that fact's geometry; the place (point or drawn
   plot) is always outlined.
5. **No verdicts without the agent.** The data layer returns facts; conclusions come only from the agent's accepted
   claims (window). The prototype shows evidence ordered by the intent profile, never "allowed / forbidden".
6. **Plain words first, the official name second**: "Reserva Ecológica Nacional (REN)", "Plano Diretor Municipal (PDM)".
7. **Status is never colour alone** — icon + word + colour (colour-blind safe, readable in print and in the video).

## 3. Layout

### Desktop (≥ 960 px)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ◆ Território Explicado   o que condiciona um terreno, com a fonte de cada facto │
│                                             [Como usar] [Sobre os dados] PT|EN │
├───────────────────────────┬──────────────────────────────────────────────────┤
│ ① Onde?                   │                                        [Camadas]│
│ [ pesquisar morada… 🔍 ]   │                                           [+]    │
│ Toca no mapa · [Desenhar  │               M A P A                     [−]    │
│ terreno] · [Exemplos ▾]   │                                                  │
│ ② O que quer fazer? [▾]   │     (local marcado · geometria do cartão         │
│ (dropdown de pretensão)   │      selecionado realçada)                       │
│ ③ Resultado               │                                                  │
│  resumo · leituras        │  ┌ legenda do realce ┐                           │
│  cartões por tema…        │  └───────────────────┘                           │
│  O que não sabemos        │ Informação, não parecer jurídico — confirme na câmara (PIP) │
└───────────────────────────┴──────────────────────────────────────────────────┘
```

Panel 400 px, scrolls on its own; the three steps stay as headings so the user always knows where they are. Step ③ is
empty-state text with examples until a place is chosen.

### Phone (< 760 px)

Map full screen; the panel becomes a **bottom sheet** with three heights (peek: current step title · half: summary and
first cards · full: everything). Header shrinks to logo + menu (Como usar, Sobre os dados, PT|EN). The search box
floats at the top of the map. Help and provenance open as full-screen sheets.

## 4. Step ① — where

- **Search** (addresses and place names in Portugal; results list with municipality); choosing one flies the map and
  runs the point query.
- **Tap the map** = point query (default mode).
- **Draw plot**: button switches the mode; taps add vertices; "Concluir" (or tapping the first vertex) closes; "Limpar".
  Area shown live while drawing (ha). Limit 1 000 ha, stated before the user hits it.
- **Examples** (the golden cases): "Terreno agrícola em Santo Varão", "Pinhal de Ofir", … — one tap runs them. This is
  the judge's fastest path.
- Outside the pilot regions the query still runs; the summary says what is national (CAOP, global land cover) and what
  is not covered.

## 5. Step ② — intent

A **dropdown** (native `<select>`, full width, labelled "O que quer fazer?") with the intents of `data/pretensoes.json`
(`intents[].label.pt|en`): Construir habitação · Apoio agrícola · Agricultura · Floresta · Fotovoltaico · Comprar ·
Riscos · Descrever (default). All options are readable at once and the phone opens its own picker — a row of chips hid
half of them behind a horizontal scroll (changed after testing, 2026-09-28). Changing the intent **re-orders and
re-labels** the cards — it never re-queries — and updates the shareable link:

| Role in the profile | Card tag | Order |
|---|---|---|
| `bloqueante` | "Pode impedir" | first |
| `condicionante` | "Acrescenta condições" | second |
| `contexto` | "Contexto" | last |

The tag's tooltip is the profile's `why` text. Thresholds typed LEGAL are shown only after human validation; until
then they read "a confirmar".

## 6. Step ③ — result

### 6.1 Summary (top of the panel)

`Freguesia, Concelho` · point or plot (area in ha) · coverage badge ("nas regiões piloto" / "fora — só dados nacionais")
· intent. Then **3–5 key readings**: deterministic one-liners built from facts, most important first for the intent —
e.g. "Dentro da REN em 38 % do terreno", "PDM: Solo Rústico — Espaço Agrícola", "Perigosidade de incêndio: alta",
"Declive: 62 % plano". Facts, not verdicts. A card's reading here is its **strongest row** (status first, then the
largest share), never simply the largest share: a plot that is 58 % low and 18 % high flood hazard reads "Alto — 18 %"
(the majority row hid the higher hazard — found in testing, 2026-09-28). In the window this block is replaced by the
agent's answer, each sentence linked to its cards.

### 6.2 Cards by theme

| Theme | Datasets (`facts_at` / `facts_for` `dataset · attribute`) |
|---|---|
| Ordenamento | `dgt_crus · land_use_plan_class` |
| Condicionantes legais | `dgt_ren · ecological_reserve`, `dgt_ran · agricultural_reserve`, `icnf_areas_protegidas · protected_area` |
| Riscos — incêndio | `icnf_perigosidade · fire_hazard_class`, `icnf_areas_ardidas · burned_area / burn_history`, `ipma_rcm · fire_risk_forecast_snapshot` |
| Riscos — cheias | `apa_zonas_inundaveis · flood_extent`, `apa_perigo · flood_hazard_class`, `apa_arpsi · designated_flood_risk_area`, `apa_marcas_cheia · flood_mark_nearby` |
| Terreno | `mdt_lidar2024` (or `cop_dem30` fallback) `· slope_pct / slope_class / aspect / aspect_class / elevation_m`, `cos2025` / `cos2023 · land_cover`, `mconst_lidar2024 · building_footprint / buildings_in_plot / buildings_nearby` |
| Evolução | `cos1995 / cos2018 / cos2023 / cos2025 · land_cover` as a timeline (1995 compared at level 1 only) |
| Contexto | `ine_bgri2021 · census_subsection(s)`, `ine_precos_habitacao · median_price_eur_m2_*` |
| Localização | `caop2025 · freguesia`, `pilot_regions · coverage` |

**Card anatomy:** plain title · value in bold · for plots a share bar ("38 % do terreno") · status pill · intent tag ·
source chip (e.g. "DGT · 2024") · "Ver no mapa". Several values of one dataset (a plot crossing two PDM classes) stay in
one card as rows, largest share first.

**Status pills** (icon + word + colour). The status, the card's one-line reading and the pill word come from the data
layer — columns `level`, `label_pt` / `label_en` and `tag_pt` / `tag_en` of `facts_at` / `facts_for` (`data/schema.sql`,
2026-09-28); the UI never parses the English `value` (the agent's evidence text). A NULL tag means the level's own word:

| Pill | Meaning | Colour |
|---|---|---|
| ● Dentro / Parcial | inside a legal constraint or a high hazard class (with the share) | red |
| ◐ Condiciona | medium hazard, burned, ARPSI, near a constraint (a REN watercourse line < 100 m), rule-dependent | amber |
| ○ Fora | outside — **only where the layer is loaded for that municipality** | green |
| ⊘ Não disponível | layer not published / not loaded here — not consulted | grey |
| ℹ Informativo | context value (census, price, elevation) | blue |

### 6.3 What we don't know

Always present when non-empty, never hidden in a card: layers not available here (with the reason), relief answered by
the Copernicus fallback, flood maps that only cover studied river stretches, census values not area-weighted, building
counts cut by the edge of the loaded area. Each item comes from a fact — `level = na`, or its `caveat` code
(`relief_fallback`, `ren_lines_unpublished`, `census_whole_subsections`, `pilot_edge`) — or from a meaningful absence
(no flood-map row where the layer is loaded); a new code needs its sentence in both languages.

### 6.4 Provenance drawer (from a source chip)

Dataset title · publisher · licence · reference date · retrieved · coverage and known gaps · SQL (`sql_hint`,
copyable) · diploma and PDF link (REN/RAN) · link to "Sobre os dados". In the window it also shows the claim → evidence
chain from the explanation graph.

## 7. Map

- Basemap: light OSM style; orthophoto optional later (`data/sources.md`).
- **Place**: point marker or plot outline (brand colour, always on top).
- **Highlight**: the selected card's geometry (fill + outline, legend bottom-left "REN — parte do terreno"); the map fits
  it with padding; deselect by clicking the card again or the map.
- **Layers button** (top right): REN, RAN, perigosidade, zonas inundáveis, áreas protegidas, edifícios (from zoom 15),
  sombreado do relevo. Off by default except the highlight; each with a one-line legend.
- **"À volta" grid** (from a result): cells coloured by the data layer's facts (prototype) / by the rule engine (window);
  the legend states "cinzento = sem dados, não é livre". Clicking a cell fills the panel with that cell's facts (no
  popups — popups hide the map and do not work on phones).

## 8. Help

- **First visit**: a 3-step overlay ("1 Escolhe um sítio · 2 Diz o que queres fazer · 3 Lê a resposta e as fontes"),
  "Não mostrar outra vez" (remembered in the browser).
- **Como usar** drawer = the user manual (`docs/manual.md`): getting started, reading the answer, plots and shares, the
  grid, "não disponível ≠ livre", glossary, FAQ, limitations and legal notice.
- **Sobre os dados** drawer: one searchable table from `open.dataset_meta` grouped by theme (entity, reference date,
  licence, coverage, gaps) — the long source list lives here, not in the panel.
- Fixed footer line: "Informação, não parecer jurídico — confirme na câmara municipal (Pedido de Informação Prévia)".

## 9. Language, format and accessibility

- PT-PT default, EN toggle; the toggle keeps the query. Data values (PDM class names, land cover, place names,
  diplomas) stay in Portuguese and are labelled as such in EN; ordinal classes are translated in EN (fire and flood
  hazard, IPMA risk, slope classes, compass sectors SO/O/NO → SW/W/NW).
- Portuguese number format in PT (1 234,5 · 38 %), English in EN; areas in ha, slope in %, aspect in compass sectors.
- Keyboard: every control reachable, visible focus, Escape closes drawers; results announced (`aria-live`); contrast AA;
  light and dark themes follow the system.
- States: empty (intro + examples), loading (skeleton cards, never a frozen map), error (message + retry), outside the
  regions, point on water.

## 10. Window additions (not in the prototype)

Agent answer at the top with sentences linked to cards · explanation-graph tab (conclusion ← link ← rule ← evidence ←
dataset, with the Challenger's verdict) · trace tab by role with revisions · unknowns with the reason chosen by the
agent · sample-mode banner when no keys are set.

## 11. Acceptance (what a judge must be able to do)

| # | Task | Target |
|---|---|---|
| 1 | Understand what the page does without help | header + empty state, < 30 s |
| 2 | Run a first query | one tap on an example, < 60 s from landing |
| 3 | Find why a statement is true | card → source chip → SQL / diploma in ≤ 2 clicks |
| 4 | See which part of the plot a value covers | "Ver no mapa" highlights it |
| 5 | Tell "not available" from "outside" | grey pill + text, never green |
| 6 | Use it on a phone | bottom sheet, no horizontal scroll, tap targets ≥ 44 px |
| 7 | Point < 1 s, plot < 2 s, grid < 2 s | measured on the deployed URL |
