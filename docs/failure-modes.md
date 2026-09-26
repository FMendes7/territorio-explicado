# Failure modes

Required by the submission rules ("a written description of the failure modes you found") and a bonus
criterion ("documenting failure modes other teams can learn from"). Format per entry:
**what we observed → why it happens → what we did (or could not do) about it**. Entries found during the
private rehearsal are marked *(rehearsal)*; entries found inside the window are dated.

## Known before the window (from design and rehearsal)

1. **Geocoding is not ground truth** *(rehearsal, 2026-09-26)* — Nominatim resolves "Paço das Escolas, Coimbra" to the Porta Férrea, ~200 m from the courtyard; two hundred metres can move a point across a freguesia or land-cover boundary → the agent reports the geocoded point, its display name and a confidence flag as an evidence item, and asks for a map click when the address is ambiguous (several candidates, or a village name that exists in more than one municipality).
2. **A live source can be down while its catalogue entry looks fine** *(rehearsal)* — the DGT WFS for the fire-hazard map answers `GetCapabilities` but fails every `GetFeature` → the platform loads from the official zip instead; at run time the agent never depends on a live WFS, and every dataset row carries `retrieved_at` so the answer can say how old the copy is.
3. **Licence metadata disagrees between portals** *(rehearsal)* — the fire-hazard map is CC BY 4.0 on dados.gov.pt and "consultation only" in the ICNF geocatalogue → the answer's provenance shows both statements; the agent must not present a licence as a fact when its sources conflict.
4. **"Flood zone" layers are not flood extents, and even flood extents are not "safe/unsafe"** *(rehearsal)* — the first APA layer loaded held only 5 designated flood-risk blocks (ARPSI) in three regions; it was replaced by the PGRI 2nd-cycle hazard classes and per-return-period extents. Still, these maps exist only for the studied ARPSI stretches: a point outside every polygon is *not* "safe from flooding" → the agent says "not inside a mapped flood zone (APA PGRI 2022–2027, which covers only studied areas)", cites nearby historical flood marks when they exist, and never says "no flood risk".
5. **Outside the pilot regions the database is silent, not negative** *(design)* — CAOP is national, the other layers are not; a point in Porto returns a municipality and nothing else → every layer that is not loaded for that area must be listed under *unknowns*, and the agent falls back to the **global tier** (WorldCover, JRC flood, …) whose provenance says so; legal questions stay unanswerable there. Golden cases `out-001` (Porto: tier A partial), `out-002` (Madrid: tier D urban) and `out-003` (Guadarrama: tier D rural) test this.
6. **Boundary points touch several polygons** *(design)* — a point exactly on a freguesia or COS boundary intersects two features → `facts_at()` may return two rows for one attribute; the agent reports both instead of picking one silently.
7. **Municipality codes from memory were wrong 3 times out of 26** *(rehearsal)* — Mealhada, Mortágua and Terras de Bouro had wrong DICO hints; the loader's name cross-check against CAOP caught it → any code table typed by a human or a model is validated against an authoritative join before use.
8. **The PDM (municipal master plan) is the question people actually ask, and it is not loaded** *(design)* — "can I build here?" cannot be answered from the five base layers → the agent answers what it can (administration, land cover, hazards, census) and states explicitly that zoning/PDM rules were not consulted; golden case `cbr-005` tests this.

## Found inside the window

_(dated entries from 15 Oct)_
