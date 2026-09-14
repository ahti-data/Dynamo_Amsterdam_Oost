# Dynamo dashboard — plan voor versie 1

Status: **versie 1 staat en draait lokaal.** Geschreven na inspectie van de eerste CBS
RA-output (`data/output_data/output_1a/`, opgeleverd 09-09-2026); §1–5 beschrijven de
verantwoording, §6 wat er nog open staat.

Draaien:

```r
shiny::runApp("app.R")
```

Eerst eenmalig `Rscript data-prep/01_build_app_data.R` — dat zet de 330 MB CSV + 19 MB xlsx
om naar 7,6 MB parquet plus de geometrie.

Afspraken uit het overleg: **heel Amsterdam** (niet alleen Oost), in v1 **alleen
data-export** (de think-cell/favorieten-laag uit `utils/` staat klaar maar is bewust nog
niet aangesloten), en deployment naar healthinsights.ahti.nl waar Authelia de login
standaard afhandelt — dus géén shinymanager in deze repo.

---

## 1. Wat er nu staat

### Gekopieerd uit `shiny_dashboard_template`
`utils/` (8 scripts), `tests/`, `templates/` (think-cell .pptx + previews), `deploy.env`,
`.gitignore`, `.claude/skills/thinkcell-export/`.

De bestaande `dashboard/utils/format_thinkcell_download.R` was een stub van 14 regels en is
vervangen door de volledige versie (376 regels). `data/metadata/brand_colors.R` was al
identiek. De template's `.github/workflows/deploy.yml` is **niet** meegekopieerd naar
`dashboard/.github/` — dat pad draait hier nooit (zie §6, Deployment); de echte workflow staat
op de repo-root.

De bestaande `app.R` is **niet** overschreven. Dat is de prototype-versie die binnen de CBS
RA draait (verwijst naar `dt_huishoudens_agg_OT1`, `dt_rins_agg_OT2`, `st_read("wc.shp")`)
en lokaal dus niet draait. Bewaard als `app_RA_prototype.R.bak`; blijft de referentie voor
de bedoelde interactie, maar de lokale app wordt opnieuw geschreven tegen de geëxporteerde
bestanden.

### Geodata
**Niet** de `Gebieden_in_Nederland_*.csv` uit `infectieziekten_monitor_prod` — zie §5.
Wel gekopieerd naar `data/geo/`, uit `dashboard_client/data-prep/geo/` in deze repo zelf:

| bestand | features | sleutel |
|---|---|---|
| `GM0363_buurten.geojson` | 517 | `statcode` = `BU0363AA01` |
| `GM0363_wijken.geojson` | 110 | `statcode` = `WK0363AA` |
| `GM0363_gebieden.geojson` | 25 | `code` = `GA01` |

Alle drie WGS84, met `statnaam`/`naam` — dat levert meteen de **regionamen** die in de
CBS-output ontbreken (die bevat alleen codes).

---

## 2. De data, geverifieerd

### `OT_HHKIND.csv` — 3.032.924 rijen, 330 MB, ASCII
| kolom | waarden |
|---|---|
| `population` | `huishoudens_met_kinderen` |
| `year` | 2018–2024 |
| `variable_name` | `R_MPG1_armoede_hh` … `R_MPG9_wanbet_zv_hh`, `R_MPG_totaal` (10) |
| `variable_value` | `0`, `1`, `2`, `3plus` |
| `metric_name` | `n_households`, `n_kinderen_hh`, `n_kinderen_0tot2_hh`, `n_kinderen_2tot4_hh`, `n_kinderen_4tot12_hh`, `n_kinderen_12tot18_hh` (6) |
| splitvariabelen | `kinderopvangtoeslag_hh` (0/1), `migratieachtergrond_hh` (0/1), `langwonende_hh` (0/1), `O_MPG_combination` (9) |
| `region_agg_level` | `bc`, `wc`, `gebiedcode`, `stadsdeel`, `gemeente` |

### `OT_OUD.xlsx` — 427.088 rijen, 268 MB uitgepakt XML
| kolom | waarden |
|---|---|
| `population` | `ouderen (65+)` |
| `year` | 2018–2024 |
| `variable_name` | `R_OUD_totaal`, `R_OUD1_armoede`, `R_OUD2_migratieachtergrond`, `R_OUD3_hhwijziging`, `R_OUD4_alleenwonend`, `R_OUD5_geenkind` (6) |
| `variable_value` | `0`, `1`, `2`, `3plus` |
| `metric_name` | `n_ouderen_with_var_value` (1) |
| splitvariabelen | `herkomst7` (8), `geslacht` (M/V), `O_OUD_combination` (9) |

> **Afwijking t.o.v. het outputformulier:** het formulier noemt `langwonende_hh` als kolom in
> `OT_OUD`; die kolom zit er niet in. `OT_OUD` heeft drie splitvariabelen, niet vier.

### Drie structurele eigenschappen die het ontwerp bepalen

**(a) Splitvariabelen zijn marginaal — nooit twee tegelijk.**
Van de 3.032.924 HHKIND-rijen hebben er 2.672.741 precies één splitvariabele ≠ `all` en
360.183 er geen. Nul rijen hebben er twee. Idem voor OUD (379.472 / 47.616 / 0).
Een rij is dus óf een **totaalrij** (alles `all`) óf een **marginale uitsplitsing** over één
variabele. Dat sluit precies aan op het gevraagde "kies één split_by".

**(b) `n_totaal_population_in_region` is constant per regio × jaar.**
Geverifieerd: 0 van de 3.945 regio-jaarcombinaties heeft meer dan één waarde. Bruikbaar als
stabiele noemer.

**(c) De categorieën tellen alleen op tot `n_totaal` bij `metric_name = n_households`.**
Voor die metric is `sum(variable_value ∈ {0,1,2,3plus}) ≈ n_totaal` (ratio ≈ 1,0 bij 33.940
van ~39.000 groepen; afwijkingen door afronding op 10 en onderdrukking). Voor de
`n_kinderen_*`-metrics telt de teller **kinderen** en de noemer **huishoudens** — dan is
`metric_value / n_totaal` géén percentage. Zie open vraag 1.

### Regiovintage: één set grenzen is correct
Weesp zit in **alle** jaren 2018–2024, ook vóór de annexatie in 2022. De pipeline heeft de
huidige indeling dus teruggelegd op alle jaren. Eén geojson-vintage voor de hele reeks is
daarmee juist, geen benadering. Het aantal buurten per jaar varieert (416 → 427) door
onderdrukking, niet door grenswijzigingen.

### De koppeling data ↔ geometrie sluit volledig
| niveau | codes in data | in geojson | data zonder geometrie | geometrie zonder data |
|---|---|---|---|---|
| `bc` (buurt) | 440 | 517 | **0** | 77 (grijs) |
| `wc` (wijk) | 109 | 110 | **0** | 1 (Westpoort, grijs) |
| `gebiedcode` | 25 | 25 | **0** | 0 |

Er verdwijnt dus niets van de kaart. De koppeling is `BU`/`WK` als prefix voor buurt/wijk,
exact voor gebied.

**Stadsdeel heeft geen eigen bestand**, maar is afleidbaar: de letter in de code bepaalt het
stadsdeel (A=Centrum, B=Westpoort, E=West, F=Nieuw-West, K=Zuid, M=Oost, N=Noord, S=Weesp,
T=Zuidoost). Negen letters, negen stadsdelen in de data — sluitend. De prep-stap dissolveert
de wijken tot stadsdeelgeometrie.

---

## 3. Architectuur

### Prep-stap (eenmalig, buiten de app) — `data-prep/01_build_app_data.R`
Draait handmatig na elke nieuwe RA-levering. Doet:

1. `fread()` op de CSV; `readxl::read_xlsx()` op de xlsx (eenmalig traag, daarna niet meer).
2. **Beide tabellen naar één schema.** Omdat er nooit twee splits tegelijk zijn, kan de brede
   split-kolommenset smal:
   ```
   population, region_level, region_code, region_name, stadsdeel,
   year, variable_name, variable_value, metric_name, metric_value,
   n_totaal, split_var, split_level, denominator
   ```
   Totaalrijen krijgen `split_var = "(totaal)"`. Dit maakt de UI generiek: HHKIND (4 splits)
   en OUD (3 splits) worden door dezelfde code bediend.
3. Regionamen en stadsdeel aanhaken vanuit de geojson.
4. `denominator` vooraf berekenen (zie open vraag 1).
5. Wegschrijven als **parquet, gepartitioneerd op `population` / `region_level`**. De app
   leest lazy via `arrow` en haalt per slice alleen de benodigde partitie op — dan hoeft
   3,5 mln rijen nooit volledig in geheugen, wat schaalt als er meerdere gebruikers tegelijk op
   de server zitten.
6. Geometrie: drie geojson + afgeleide stadsdeellaag, vereenvoudigd (`st_simplify`) voor
   snelheid in de browser, weggeschreven als `data/app_data/geo.rds`.

De ruwe 330 MB CSV en 19 MB xlsx blijven buiten git (`.gitignore`); de parquet-output is
klein genoeg om wél mee te deployen.

### App — `app.R`
Eén hoofdtab **"Iteratie 1"**, daarbinnen twee subtabs. Eén gedeelde parameter bovenaan:
**populatie** (`ouderen (65+)` / `huishoudens met kinderen`), die de keuzelijsten van beide
subtabs vult.

#### Subtab 1 — Kaart
Besturing: jaar · regioniveau (buurt / wijk / gebied / stadsdeel) · indicator
(`variable_name`) · waarde (`variable_value`) · metric · split_by (+ welk niveau daarvan) ·
absoluut/relatief.

`leaflet` choropleth: hover-tooltip met naam + waarde + n, klik-popup met de volledige
context, legenda, en **grijs met expliciet "onvoldoende waarnemingen"** voor onderdrukte
regio's — belangrijk dat onderdrukt niet als nul leest.

#### Subtab 2 — Per regio
Besturing: regioniveau + regio · indicator · metric · split_by.

`plotly` lijndiagram 2018–2024, één lijn per niveau van de gekozen splitvariabele (bij
"(totaal)" één lijn). Hover met jaar + waarde. Zelfde absoluut/relatief-keuze.

---

## 4. Werkvolgorde

1. `data-prep/01_build_app_data.R` + parquet/geo-output — de basis waar al het andere op rust.
2. Kaart-subtab, alleen totalen (zonder split) — eerst de koppeling zichtbaar goed krijgen.
3. Split_by toevoegen aan de kaart.
4. Per regio-subtab.
5. Absoluut/relatief.
6. Onderdrukkingslogica + legenda-afwerking.
7. Pas daarna: think-cell export / favorites aanhaken (zie open vraag 2).

---

## 5. Waarom niet `Gebieden_in_Nederland_*.csv`

Die bestanden zijn gecontroleerd. Het zijn **geen shapefiles** — ze bevatten geen enkele
geometrie, alleen een gemeentelijke lookup-tabel (gemeente → GGD-regio, provincie,
veiligheidsregio, COROP, enz.), één rij per gemeente. Het laagste niveau is *gemeente*.

Deze data zit op buurt-, wijk-, gebied- en stadsdeelniveau *binnen* Amsterdam. Die bestanden
kunnen daar dus niets voor tekenen. De geojson die dat wél kan stond al in deze repo, onder
`dashboard_client/data-prep/geo/`, en is geverifieerd sluitend op de datacodes.

(Ook bekeken: `geo_data.rda` in dezelfde map, 760 KB — te klein voor buurtgeometrie van heel
Nederland en op gemeenteniveau opgezet.)

---

## 6. Gemaakte keuzes en wat er nog open staat

### De noemer bij "Aandeel (%)" — gekozen definitie

`metric_value` gedeeld door de som over de `variable_value`-categorieën binnen dezelfde
regio × jaar × indicator × metric × splitniveau (kolom `denominator`, vooraf berekend in de
prep-stap).

Dat leest als een conditioneel aandeel: *"van de huishoudens mét migratieachtergrond heeft
x% armoede"*. Bewust niet `n_totaal`, want bij de `n_kinderen_*`-metrics telt de teller
kinderen en `n_totaal` huishoudens — dan is de uitkomst geen percentage. De gekozen noemer
blijft voor élke metric een geldig percentage. `n_totaal` gaat wel mee in de tooltip
("n = x van y") en in de export, zodat de andere breuk altijd na te rekenen is.

Voor `metric_name = n_households` vallen beide definities samen: de categorieën tellen daar
op tot `n_totaal` (Amsterdam 2024, R_MPG_totaal: 38.610 + 26.660 + 13.910 + 8.340 = 87.520).

### Nog open

1. **Wanneer de think-cell/favorieten-laag aangesloten wordt.** `utils/` is compleet
   meegekomen; het aansluiten is stap 7 uit §4.
2. **Labels voor de indicatoren.** Nu worden de kolomnamen opgeschoond weergegeven
   (`R_MPG1_armoede_hh` → "MPG1 - armoede"). Als er een vastgestelde Nederlandse
   omschrijving per indicator is, is dat een betere bron dan de variabelenaam.
3. **`variable_value` = `3plus`.** Wordt nu getoond zoals hij is. Voor de stapelings-
   variabelen betekent het "3 of meer risicofactoren"; voor de binaire varianten komt de
   waarde niet voor. Eventueel expliciet labelen.

### Deployment

**Staat live.** `deploy.env` → `APP_FOLDER=dynamo_internal`, dus `/apps/dynamo_internal/` op
healthinsights.ahti.nl. Niet `dynamo`: die naam is al in gebruik door het client-dashboard
(`dashboard_client/`).

De GitHub Actions-workflow die dit uitvoert staat niet onder `dashboard/.github/workflows/`
(GitHub Actions leest alleen `.github/workflows/` op de repo-root, dus die kopie — zoals de
template hem meelevert — draaide hier nooit echt en is verwijderd). De werkende versie staat op
de root: [.github/workflows/deploy-dynamo-internal.yml](../.github/workflows/deploy-dynamo-internal.yml),
naar het patroon van `pharm` en `RVS_laatste_1000_dagen` (twee andere Shiny-dashboards met
dezelfde `dashboard/`-submapstructuur als deze repo). Triggert op een push naar `main`
(path-filter `dashboard/**`) en op handmatige dispatch; synct `app.R`, `data/`, `utils/` en
`templates/` via SFTP — niet `state/`.

Daarvoor moest `data/app_data/` (de parquet-dataset, ~7,6 MB) van gitignored naar gecommit: de
CI-runner checkt de repo vers uit en heeft dus nooit toegang tot lokaal gebouwde bestanden. Dat
volgt hetzelfde patroon als `RVS_laatste_1000_dagen` en `pharm`, die hun werkdataset ook gewoon
in git zetten — het blijft dezelfde geaggregeerde, al-afgeronde/onderdrukte CBS-output die de
RA al vrijgaf, alleen anders geordend. De ruwe 330 MB/19 MB-levering in `data/output_data/`
blijft wél lokaal-only.

Aanname: de repo-secrets `FTP_USERNAME`/`FTP_SERVER`/`FTP_PASSWORD` bestaan al (dezelfde namen
worden al gebruikt door `.github/workflows/deploy-dynamo.yml` voor het client-dashboard) — niet
vanaf hier te verifiëren zonder `gh` op deze machine.
