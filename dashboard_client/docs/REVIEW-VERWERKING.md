# Verwerking review (verbeteringen.md) — status per punt

**Datum:** 10 juli 2026 · **Uitgevoerd door:** strategie-consultant + specialistenteam
**Beoordeling:** de review is grondig en de vier P0-bevindingen zijn alle tegen de data/code geverifieerd en bevestigd. Hieronder per punt wat is doorgevoerd en wat bewust backlog is.

## Doorgevoerd

| # | Punt | Wat is gedaan |
|---|------|---------------|
| P0-1 | Ouder-Amstel crash | Drempels aangepast (1-wijkgemeenten tellen mee); lege-datasetstatus, foutmelding met "opnieuw proberen" en React error boundary toegevoegd. Geverifieerd: Ouder-Amstel opent in alle views. |
| P0-2 | Jaarlogica | Beschikbaarheid wordt nu **dynamisch per scope × niveau** bepaald (`availableYears`), alle views gebruiken dezelfde logica; peiljaar is een globale selectie in de contextbalk; afwijkend weergegeven jaar wordt prominent gemeld met de beschikbare jaren. Geverifieerd: 2016 in Oost toont overal 2016. |
| P0-3 | Indicatorrichting | Elke indicator heeft nu `direction: hoog/laag/neutraal` (laag: inkomen, mediaan vermogen, arbeidsparticipatie; neutraal: huishoudensgrootte, dichtheid, herkomst NL, hh. zonder kinderen). Ranglijsten sorteren op sterkste signaal, kaartkleuring keert om bij 'laag' (donker = laag) met legenda-uitleg, standaardselecties en teksten volgen de richting. |
| P0-4 | Eén-wijkaggregaten | Sloterdijk Nieuw-West en Bijlmer-West hebben nu gevulde aggregaten; dekking (`members`) zit in het datamodel en wordt gemeld ("dit focusgebied bestaat uit één wijk, dekking 1/1"). |
| 9 | Referenties consistent | Kaart én Tabel hebben dezelfde referentiekeuze (gemeente/focus); relatieve weergave van absolute aantallen is overal uitgeschakeld (tabel toont ze grijs/absoluut met uitleg); CSV exporteert exact de schermmodus incl. referentie in de kolomkop. |
| 10 | Bestuurlijke labels | Weesp heet "Stadsgebied Weesp"; scopegroepen heten "Stadsdelen & stadsgebied" en "GGW-gebieden"; Westpoort staat gelabeld als "(buiten de 25 GGW-gebieden)". GGW-totalen zijn gedocumenteerd als benadering uit CBS-wijken (zie AANNAMES §1). |
| 11 | Aggregaten | Mediaan vermogen wordt **niet meer** als aggregaat getoond (medianen zijn niet optelbaar); dekking per aggregaat vastgelegd. Exacte noemers per indicator blijven een beperking van de CBS-bron (gedocumenteerd). |
| 12 | Many-to-many thema's | Themalidmaatschap loopt nu via de themalijst (`indicatorIds.includes`), niet via één toegewezen thema; een indicator die in meerdere thema's zit werkt in elk thema; bij themawissel blijft een gedeelde indicator behouden. |
| 13 | Contextbalk + URL | Gemeente, focus, niveau en peiljaar staan in één contextbalk; de volledige selectie (incl. view, thema, indicator) staat in de URL en is deelbaar/reproduceerbaar. |
| 14 | Lege buurtweergaven | Indicatoren zonder data op het gekozen niveau zijn uitgeschakeld in de keuzelijsten ("— geen data op dit niveau"); lege staten tonen een knop "Bekijk deze indicator op wijkniveau". |
| 15 | Trends reproduceerbaar | De trenddelta eindigt in het gekozen peiljaar en toont expliciet begin- én eindjaar (bijv. "2016–2024"). |
| 16 | Mobiel | Breakpoints toegevoegd (nav scrollbaar, controls onder elkaar, compacte paddings). Geverifieerd: geen horizontale overflow op 390 px. |
| 17 | WCAG (kern) | Zichtbare `:focus-visible`-stijlen; kaartvlakken, staafrijen en tabelrijen zijn met Enter/Spatie te bedienen; tooltips verschijnen ook bij toetsenbordfocus; SVG's hebben toegankelijke namen; contrast van as-/hulptekst verhoogd naar ≥ 4,5:1. |
| 19 | Kaartklassen | De kleurschaal staat in absolute modus vast over alle beschikbare jaren (jaarvergelijking behoudt betekenis), met vermelding in de kaarttekst; de legenda heeft een "geen data"-klasse. Vaste inhoudelijke klassegrenzen per indicator: backlog (vergt domeinkeuzes met Dynamo). |
| 20 | Gemeentedekking eerlijk | De footer toont expliciet de dekking (35 gemeenten: alle ≥100.000 inwoners + Amsterdamse buurgemeenten); README en Verantwoording beschrijven dit en de uitbreidingsprocedure (`GEMEENTEN` + `fetch_geo.py`). |
| 21 | Kwaliteitsbewaking (basis) | `data-prep/check_data.py`: dataregressietests op alle acceptatiecriteria (elke gemeente bruikbaar, 2016-Oost, één-wijkgebieden, mediaan, geometrie↔regiocodes, somcontrole). Ving direct een echte fout: Zaanstad-buurtgeometrie stond op de 2023-indeling — hersteld met `fetch_geo.py` (2025-indeling voor alle gemeenten). Volledige CI: backlog. |
| 22 | Serverpakket | `deploy/Dockerfile` (multi-stage build → nginx) en `deploy/nginx.conf` (gzip, cacheheaders, securityheaders, healthcheck `/healthz`). |
| 23 | Performance/fouten | Logo's verkleind (ahti 668 kB → 32 kB); `AbortController` op gemeentewissel; fout-states met "opnieuw proberen"; error boundary. |
| 24 | Tekstconsistentie | Bronvermeldingen overal 2016–2025; `fetch_geo.py` legt de geometriebron en -jaargang in code vast. Volledig provenance-manifest met checksums: backlog. |
| 5 | Terminologie | De tool presenteert zich in de footer expliciet als "signalerings- en verkenningsinstrument"; kaartteksten spreken van signaal, niet van advies. |

## Bewust backlog (vergt input van Dynamo of nieuwe databronnen)

| # | Punt | Waarom nu niet |
|---|------|----------------|
| 6 | Dienstspecifiek afwegingskader met gewichten | Gewichten en drempels zijn inhoudelijke keuzes die met Dynamo ontworpen en gevalideerd moeten worden; een onverklaarde totaalscore is schadelijker dan geen score. |
| 7 | Locatie-informatie (eigen locaties, bereik, capaciteit, vastgoed, prognoses) | Vergt niet-publieke Dynamo-data en afspraken over privacy; de CBS-laag is er klaar voor (levels/scopes zijn generiek). |
| 8 | Gebiedsprofiel, shortlist, zij-aan-zijvergelijking | Zinvol zodra 6/7 er zijn; anders vergelijkt de shortlist alleen demografie. |
| 10 | BBGA als officiële gebiedsbron; crosswalk Noordelijke IJ-oevers-West | BBGA-integratie is een eigen datapijplijn; huidige GGW-totalen zijn gedocumenteerd als benadering. |
| 19 | Inhoudelijke vaste klassegrenzen per indicator | Vergt normatieve keuzes (wat is "hoog"?) — samen met Dynamo bepalen. |
| 20 | Landelijke gemeentedekking | Bewuste pilotkeuze; procedure voor uitbreiding is gedocumenteerd. |
| 21 | Volledige CI (lint, componenttests, e2e, a11y-scan) | Vergt een repository/CI-omgeving; de dataregressietests zijn de eerste laag en draaien lokaal. |
| 24 | Provenance-manifest met checksums | Nuttig bij overdracht naar beheer; nu gedeeltelijk gedekt door README + AANNAMES. |

## Acceptatiecriteria — stand

- ✅ Iedere gemeentekeuze opent zonder consolefout (incl. Ouder-Amstel; lege status aanwezig).
- ✅ 2016 in Oost toont in alle views 2016-data; afwijkingen worden prominent gemeld, nooit stil.
- ✅ Sloterdijk Nieuw-West en Bijlmer-West hebben geldige aggregaten met dekking 1/1.
- ✅ Sortering, kaartkleur en duiding respecteren de indicatorrichting.
- ✅ Absolute aantallen worden nergens als procentuele afwijking gepresenteerd (kaart én tabel én CSV).
- ✅ Indicatoren zonder buurtdata zijn niet selecteerbaar op buurtniveau.
- ✅ De trenddelta eindigt in het gekozen peiljaar en toont begin- en eindjaar.
- ✅ 25 GGW-gebieden herkenbaar; Westpoort zichtbaar erbuiten; Weesp als stadsgebied.
- ✅ Kernflow toetsenbordbedienbaar met zichtbare focus.
- ✅ Geen horizontale overflow op 390 px.
- ◐ Kwaliteitsbewaking: dataregressies draaien lokaal (`python data-prep/check_data.py`); CI-integratie is backlog.
