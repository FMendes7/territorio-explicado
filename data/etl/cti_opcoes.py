#!/usr/bin/env python3
"""data/etl/cti_opcoes.py — the CTI's strategic options as approximate REFERENCE geometries (Tier 3; blind benchmark).

What: georeferences the layout drawings of the Comissão Técnica Independente (final report PT2, Annex 12 "Layouts",
    aeroparticipa.pt/relatorios/PT2-Anexo12.pdf) and writes, per strategic option, the runways and the airport limit
    into ref.cti_opcoes of the LOCAL database — a schema the agent's role (territorio_ro) cannot read, so no tool of the
    agent can see the answer (evals/README.md, blind rule; docs/site-selection.md §12). Method per layout: the page is
    rendered at 300 dpi and turned north-up; the runways are found by their colour (RGB 221,110,0); their ends are
    paired with the drawing's own table of runway-threshold coordinates (WGS84) and a 4-parameter similarity
    (pixel → EPSG:3763) is fitted — the residuals are printed and stored; runways are then drawn from the published
    threshold coordinates themselves, and the airport limit from vertices picked by hand on a pixel grid, through the
    fitted similarity. AHD (Humberto Delgado) is the COS 2025 "Aeroportos" (1.5.3.1) polygons around Portela (open
    data). The CTA "alternative" and the 3- and 4-runway variants are not digitised.
Depends on: data/raw/cti/PT2-Anexo12.pdf and data/raw/cti/cti_transcricao.json (the hand transcription: threshold
    tables and limit vertices — CTI material, reuse terms unconfirmed, never in git); pdftoppm (poppler-utils); Python
    numpy, scipy, Pillow, pyproj; psql with PG_DSN (password via PGPASSWORD/.pgpass); open.cos_serie (COS 2025).
Used by: the eval runner (window) — after the agent has answered; nothing in `open`, data/views.sql or schema.sql
    reads `ref`.
Ao mexer: never GRANT anything on schema ref to territorio_ro and never copy ref.* into `open` or into the sample
    extract; the geometries stay off the public repo until the CTI's reuse terms are confirmed (only this script and
    its description are public).
"""
import itertools
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image
from pyproj import Transformer
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "data/raw/cti"
PDF = RAW / "PT2-Anexo12.pdf"
TRANS = RAW / "cti_transcricao.json"
TO_3763 = Transformer.from_crs(4326, 3763, always_xy=True)
RUNWAY_RGB = (221, 110, 0)
MAP_XMAX = 2080          # right edge of the map frame on a north-up 300-dpi page (title block and legend beyond it)


def dm(s):
    """'38 45.475' (degrees, decimal minutes) → decimal degrees."""
    d, m = s.split()
    return int(d) + float(m) / 60


def page_image(page, tmp):
    """Render one PDF page at 300 dpi and turn it north-up (the drawings are landscape on portrait pages)."""
    out = Path(tmp) / f"p{page}"
    subprocess.run(["pdftoppm", "-f", str(page), "-l", str(page), "-r", "300", "-png", "-singlefile", str(PDF), str(out)],
                   check=True)
    return Image.open(f"{out}.png").rotate(-90, expand=True)


def runway_ends(img):
    """Ends of each runway drawn in RUNWAY_RGB: colour mask → components → collinear pieces merged → extreme points."""
    a = np.asarray(img.convert("RGB")).astype(int)
    m = (abs(a[:, :, 0] - RUNWAY_RGB[0]) < 30) & (abs(a[:, :, 1] - RUNWAY_RGB[1]) < 30) & (a[:, :, 2] < 50)
    m[:, MAP_XMAX:] = False
    lab, n = ndimage.label(m)
    runs = []
    for i in range(1, n + 1):
        ys, xs = np.nonzero(lab == i)
        if len(xs) < 1500:
            continue
        P = np.c_[xs, ys].astype(float)
        c = P.mean(0)
        u = np.linalg.svd(P - c)[2][0]
        for r in runs:
            d = c - r["c"]
            if abs(d[0] * r["u"][1] - d[1] * r["u"][0]) < 12 and abs(np.dot(u, r["u"])) > 0.999:
                r["P"] = np.r_[r["P"], P]
                break
        else:
            runs.append({"c": c, "u": u, "P": P})
    ends = []
    for r in runs:
        t = (r["P"] - r["c"]) @ r["u"]
        ends += [r["c"] + t.min() * r["u"], r["c"] + t.max() * r["u"]]
    return ends


def similarity(px, xy):
    """Least-squares 4-parameter similarity, image pixels (y down) → EPSG:3763 metres; returns f, scale, rotation°, residuals."""
    A, B = [], []
    for (x, y), (X, Y) in zip(px, xy):
        A += [[x, y, 1, 0], [-y, x, 0, 1]]
        B += [X, Y]
    a, b, tx, ty = np.linalg.lstsq(np.array(A, float), np.array(B, float), rcond=None)[0]
    f = lambda x, y: (a * x + b * y + tx, b * x - a * y + ty)
    res = [float(np.hypot(*(np.array(f(*p)) - w))) for p, w in zip(px, xy)]
    return f, float(np.hypot(a, b)), float(np.degrees(np.arctan2(b, a))), res


def georef(img, soleiras):
    """Pair the detected runway ends with the threshold table: the assignment with the smallest residual among the
    north-up ones (|rotation| < 3°, 2.5–4 m per pixel at 1:25 000); with one runway, the one closest to north-up."""
    xy = [TO_3763.transform(-dm(lon), dm(lat)) for _, lat, lon in soleiras]
    ends = runway_ends(img)
    best = None
    for perm in itertools.permutations(range(len(ends)), len(xy)):
        f, s, rot, res = similarity([ends[i] for i in perm], xy)
        if abs(rot) > 3 or not 2.5 < s < 4:
            continue
        score = max(res) if len(xy) > 2 else abs(rot)
        if best is None or score < best[0]:
            best = (score, f, s, rot, res)
    if best is None:
        sys.exit(f"no north-up fit for {len(ends)} runway ends — check the transcription")
    return best[1:], xy


def wkt_line(pts):
    return "LINESTRING(" + ", ".join(f"{x:.2f} {y:.2f}" for x, y in pts) + ")"


def main():
    dsn = os.environ.get("PG_DSN") or sys.exit("set PG_DSN (local database only)")
    T = json.loads(TRANS.read_text())
    rows = []
    with tempfile.TemporaryDirectory() as tmp:
        for key, L in T["layouts"].items():
            (f, s, rot, res), xy = georef(page_image(L["pagina"], tmp), L["soleiras"])
            note = f"scale {s:.3f} m/px, rotation {rot:+.3f}°, residuals {', '.join(f'{r:.0f}' for r in res)} m"
            print(f"{key}: {note}")
            pairs = [xy[i:i + 2] for i in range(0, len(xy), 2)]   # thresholds 1–2 and 3–4 are the two ends of a runway
            geom = "MULTILINESTRING(" + ", ".join(wkt_line(p)[10:] for p in pairs) + ")"
            rows.append((key, L, "pistas", geom, "threshold coordinates of the drawing's own table (WGS84 → EPSG:3763)",
                         max(res), note))
            if L.get("limite_px"):
                ring = [f(x, y) for x, y in L["limite_px"]]
                ring.append(ring[0])
                rows.append((key, L, "limite_aeroporto", "POLYGON((" + wkt_line(ring)[11:] + ")",
                             "vertices picked by hand on a 100-px grid (±20 px), through the fitted similarity",
                             max(150, max(res) + 100), note + "; limit approximate (≈ ±150 m, more where the residuals are larger)"))
    comp = {k: [] for k in T["layouts"]}
    for r in rows:
        comp[r[0]].append(r)
    sql = ["\\set ON_ERROR_STOP 1",
           "CREATE SCHEMA IF NOT EXISTS ref;",
           "REVOKE ALL ON SCHEMA ref FROM PUBLIC;",
           "DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'territorio_ro') THEN "
           "EXECUTE 'REVOKE ALL ON SCHEMA ref FROM territorio_ro'; END IF; END $$;",
           "DROP TABLE IF EXISTS ref.cti_opcoes;",
           "CREATE TABLE ref.cti_opcoes (id serial PRIMARY KEY, opcao smallint NOT NULL, opcao_nome text NOT NULL, "
           "componente text, elemento text, desenho text, pagina smallint, metodo text, erro_m numeric, nota text, "
           "geom geometry(Geometry, 3763));",
           "COMMENT ON TABLE ref.cti_opcoes IS 'CTI strategic options (PT2 Annex 12 layouts) — APPROXIMATE reference "
           "geometries for the blind airport benchmark; read only by the eval runner after the agent has answered; "
           "CTI material, reuse terms unconfirmed — never copy to open, to the sample or to the public repo';"]
    q = lambda s: "'" + str(s).replace("'", "''") + "'" if s is not None else "NULL"
    for o in T["opcoes"]:
        if not o["componentes"]:
            sql.append(f"INSERT INTO ref.cti_opcoes (opcao, opcao_nome, nota) VALUES ({o['opcao']}, {q(o['nome'])}, {q(o.get('nota'))});")
        for c in o["componentes"]:
            if c == "AHD":
                sql.append(
                    "INSERT INTO ref.cti_opcoes (opcao, opcao_nome, componente, elemento, metodo, erro_m, nota, geom) "
                    f"SELECT {o['opcao']}, {q(o['nome'])}, 'AHD', 'aeroporto_existente', "
                    "'COS 2025 class 1.5.3.1 Aeroportos, polygons within 3 km of Portela (open data)', 0, "
                    "'the existing airport as mapped by the COS, not a CTI drawing', ST_Multi(ST_Union(geom)) "
                    "FROM open.cos_serie WHERE ano = 2025 AND cod_n4 = '1.5.3.1' AND ST_DWithin(geom, "
                    "ST_Transform(ST_SetSRID(ST_MakePoint(-9.1342, 38.7742), 4326), 3763), 3000);")
                continue
            for key, L, el, wkt, met, err, note in comp[c]:
                sql.append("INSERT INTO ref.cti_opcoes (opcao, opcao_nome, componente, elemento, desenho, pagina, metodo, "
                           f"erro_m, nota, geom) VALUES ({o['opcao']}, {q(o['nome'])}, {q(key)}, {q(el)}, {q(L['desenho'])}, "
                           f"{L['pagina']}, {q(met)}, {round(err)}, {q(note)}, ST_GeomFromText({q(wkt)}, 3763));")
    sql.append("SELECT opcao, opcao_nome, componente, elemento, round(erro_m) AS erro_m, "
               "round((ST_Area(geom) / 1e4)::numeric) AS ha, round(ST_Length(geom)::numeric) AS m "
               "FROM ref.cti_opcoes ORDER BY opcao, id;")
    subprocess.run(["psql", dsn, "-X", "-q"], input="\n".join(sql), text=True, check=True)


if __name__ == "__main__":
    main()
