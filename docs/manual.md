# Manual de utilização · User manual

Text shown in the app's **Como usar / How to use** drawer (`docs/ux.md` §8). Português primeiro; English below.
Pre-window document: it describes the data layer that exists today and marks what the agent adds in the window.

---

## Português

### O que é

O Território Explicado diz **o que condiciona um terreno em Portugal para aquilo que lá quer fazer** — construir,
cultivar, plantar floresta, instalar painéis solares, comprar ou só conhecer os riscos. Junta num só sítio dados
públicos que hoje estão espalhados por cinco ou seis entidades (DGT, ICNF, APA, INE, IPMA) e mostra **a fonte de
cada facto**. Quando um dado não existe para aquele sítio, diz «não disponível» — nunca «livre».

É **informação, não um parecer jurídico**. A decisão sobre uma obra é sempre da câmara municipal: para uma resposta
vinculativa, faça um **Pedido de Informação Prévia (PIP)**.

Cobertura atual: 26 concelhos — Região de Coimbra (19), Cávado (6) e Lisboa. Fora deles, só há limites
administrativos e ocupação do solo global.

### Começar em 3 passos

1. **Onde?** Escreva uma morada ou um lugar, **toque no mapa** (um ponto) ou carregue em **Desenhar terreno** e toque
   nos cantos do terreno; termine em «Concluir». Sem ideias? Abra **Exemplos**.
2. **O que quer fazer?** Escolha uma pretensão. A lista de resultados reordena-se: primeiro o que **pode impedir**,
   depois o que **acrescenta condições**, por fim o **contexto**.
3. **Leia o resultado.** Comece pelo resumo; abra os cartões que lhe interessam; toque em **Ver no mapa** para ver a
   parte do terreno a que o valor se refere e no **chip da fonte** para ver de onde vem.

### Ler o resultado

- **Resumo**: freguesia e concelho, ponto ou terreno (com a área), se está nas regiões cobertas, e as leituras
  principais.
- **Cartões por tema**: Ordenamento (PDM) · Condicionantes legais (REN, RAN, áreas protegidas) · Riscos (incêndio,
  cheias) · Terreno (declive, orientação, altitude, ocupação do solo, edifícios) · Evolução (1995 → 2025) · Contexto
  (população, preço por m²).
- **Estados**:

| Sinal | Quer dizer |
|---|---|
| ● Dentro / Parcial | o local está dentro de uma condicionante ou numa classe de risco alta (com a % do terreno) |
| ◐ Condiciona | risco médio, ou uma condição que depende da regra aplicável |
| ○ Fora | fora — **só onde a camada existe para esse concelho** |
| ⊘ Não disponível | a camada não está publicada para esse sítio; não foi consultada — **não quer dizer livre** |
| ℹ Informativo | um valor de contexto (altitude, população, preço) |

- **O que não sabemos**: a lista do que falta para aquele sítio e porquê. Leia-a sempre.

### Terrenos e percentagens

Num terreno desenhado, cada valor vem com a **parte do terreno** que ocupa («REN em 38 % do terreno»). As
percentagens de um tema podem não somar 100 % quando parte do terreno não tem dados. Os dados de população vêm por
subsecção estatística inteira e não são repartidos pela área (está escrito no cartão). Limite: 1 000 ha por terreno.

### «À volta» — aqui não, ali sim

Depois de um resultado, **À volta** divide a zona (500 m por omissão) em células de 50 m e mostra o que cada célula
tem. Em terrenos acima de cerca de 240 ha as células são maiores, para a grelha não passar de 2 500 células; a
legenda diz o tamanho. Serve para ver **onde as condicionantes acabam**. Cinzento é «sem dados», não «livre». Toque numa célula para
ver os factos dela no painel.

### Glossário

| Termo | Significado |
|---|---|
| **PDM** — Plano Diretor Municipal | plano da câmara que classifica o solo (urbano ou rústico) e diz que usos admite; aqui lido através da **CRUS** (Carta do Regime de Uso do Solo, DGT) |
| **REN** — Reserva Ecológica Nacional | áreas de valor ecológico ou de risco (cheias, erosão, arribas) onde muitos usos são condicionados; delimitada por concelho, com diploma próprio (DL 166/2008) |
| **Exclusões da REN** | áreas retiradas da REN pela delimitação municipal — **não** são REN |
| **RAN** — Reserva Agrícola Nacional | solos com maior aptidão agrícola, protegidos contra usos não agrícolas (DL 73/2009) |
| **Rede Natura 2000 / RNAP** | áreas protegidas europeias (ZEC, ZPE) e nacionais (parques e reservas) |
| **Perigosidade de incêndio rural** | carta do ICNF com 5 classes (muito baixa a muito alta) |
| **RCM** | risco de incêndio previsto pelo IPMA para o dia, por concelho |
| **ARPSI** | áreas de risco potencial significativo de inundação (APA) |
| **Zonas inundáveis** | áreas que inundam em cheias de 20, 100 ou 1 000 anos (só troços estudados pela APA) |
| **COS** | Carta de Uso e Ocupação do Solo (DGT): o que existe no terreno (agricultura, floresta, construído…) |
| **MDT / LiDAR** | modelo digital do **terreno** medido por laser (DGT, 2024): dá o declive do chão, sem árvores nem edifícios |
| **BGRI** | subsecções estatísticas dos Censos 2021 (INE) |
| **PIP** | Pedido de Informação Prévia à câmara: a resposta formal sobre o que pode ser feito num terreno |

### Perguntas frequentes

- **«Fora da REN» quer dizer que posso construir?** Não. Quer dizer que aquele terreno não está nos polígonos da REN
  publicados para o concelho. O PDM, outras servidões e o licenciamento continuam a aplicar-se.
- **Porque aparece «não disponível»?** Porque a entidade não publica essa camada para aquele concelho (ex.: REN de
  Condeixa-a-Nova, RAN de Lisboa) ou porque o sítio está fora das regiões cobertas. Não consultámos, por isso não
  afirmamos nada.
- **De quando são os dados?** Cada cartão tem a data no chip da fonte; a lista completa está em **Sobre os dados**.
- **Porque o declive difere de outro mapa?** Usamos o modelo do terreno LiDAR da DGT a 10 m. Onde ainda não está
  publicado (parte do Cávado) usamos um modelo de superfície (Copernicus), que mede copas e telhados — o cartão diz
  qual foi usado.
- **O ponto que marquei está numa estrada ou num rio.** O resultado é o do ponto exato; para um terreno, desenhe-o.

### Limitações e aviso legal

Três regiões piloto (26 concelhos) · dados com as datas das fontes · REN sem Condeixa-a-Nova e linhas de água da REN
só em 12 concelhos · RAN sem Lisboa · relevo LiDAR em 66 % do Cávado (resto com o modelo de superfície) · cheias só
nos troços estudados · edifícios só com a pegada (sem altura) · preços só onde o INE publica. Não substitui a câmara
municipal, o PDM em vigor nem um técnico habilitado. Fontes, licenças e datas em **Sobre os dados**.

---

## English

### What it is

Território Explicado tells you **what conditions a plot of land in Portugal for what you want to do there** — build,
farm, plant forest, install solar panels, buy, or just understand the risks. It brings together public data now
scattered across five or six agencies (DGT, ICNF, APA, INE, IPMA) and shows **the source of every fact**. When a
dataset does not exist for that place it says "not available" — never "free".

It is **information, not legal advice**. Building decisions belong to the municipality: for a binding answer, file a
**Pedido de Informação Prévia (PIP)**.

Current coverage: 26 municipalities — Região de Coimbra (19), Cávado (6) and Lisbon. Elsewhere only administrative
boundaries and global land cover are available.

### Getting started in 3 steps

1. **Where?** Type an address or place, **tap the map** (a point), or press **Draw plot** and tap the plot's corners;
   finish with "Done". No idea? Open **Examples**.
2. **What do you want to do?** Pick an intent. The results re-order: first what **can prevent it**, then what **adds
   conditions**, then **context**.
3. **Read the result.** Start with the summary; open the cards you care about; tap **Show on map** to see which part
   of the plot a value covers, and the **source chip** to see where it comes from.

### Reading the result

Summary (parish, municipality, point or plot and its area, coverage, key readings) · cards by theme (land-use plan,
legal constraints, hazards, terrain, change 1995 → 2025, context) · status: **● Inside / Partly** (inside a
constraint or a high hazard class) · **◐ Conditions** (medium hazard or rule-dependent) · **○ Outside** (only where the
layer exists for that municipality) · **⊘ Not available** (not published here; not consulted — does **not** mean
free) · **ℹ Information** (context values) · **What we don't know**: always read it.

### Plots and shares

Each value of a drawn plot comes with the **share of the plot** it covers. Shares in a theme may not add up to 100 %
where part of the plot has no data. Census values are whole statistical subsections, not area-weighted. Limit:
1 000 ha per plot.

### "Around" — not here, but there

After a result, **Around** splits the area (500 m by default) into 50 m cells and shows what each cell has, to see
**where the constraints end**. Plots above about 240 ha get larger cells, so the grid stays within 2 500 cells; the
legend states the cell size. Grey means "no data", not "free". Tap a cell to see its facts in the panel.

### Glossary

PDM (municipal land-use plan, read through DGT's CRUS) · REN (National Ecological Reserve — ecologically valuable or
hazard areas; "Exclusões" are areas taken out of it) · RAN (National Agricultural Reserve — best farming soils) ·
Natura 2000 / RNAP (European and national protected areas) · rural fire hazard (ICNF, 5 classes) · RCM (IPMA daily
fire-risk forecast) · ARPSI (areas of potentially significant flood risk, APA) · flood zones (20/100/1 000-year floods,
studied river stretches only) · COS (DGT land-use/land-cover map) · MDT / LiDAR (laser-measured terrain model, DGT
2024: slope of the ground, without trees or buildings) · BGRI (2021 census subsections, INE) · PIP (formal prior
information request to the municipality).

### FAQ

- **Does "outside the REN" mean I can build?** No. The plot is not inside the REN polygons published for that
  municipality; the land-use plan, other easements and licensing still apply.
- **Why "not available"?** The agency does not publish that layer for that municipality (e.g. REN for
  Condeixa-a-Nova, RAN for Lisbon), or the place is outside the covered regions. We did not consult it, so we claim
  nothing.
- **How recent is the data?** Every card shows the date on its source chip; the full list is in **About the data**.
- **Why does the slope differ from another map?** We use DGT's LiDAR terrain model at 10 m; where it is not published
  yet (part of Cávado) a surface model (Copernicus) answers, and the card says so.

### Limitations and legal notice

Three pilot regions (26 municipalities) · data as dated by each source · REN missing for Condeixa-a-Nova and REN
watercourse lines in 12 municipalities only · RAN missing for Lisbon · LiDAR relief on 66 % of Cávado · flood maps only
on studied stretches · buildings are footprints (no height) · prices only where INE publishes them. It does not replace
the municipality, the plan in force or a qualified professional.
