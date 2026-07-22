# Externe databronnen voor de Dynamo-gebiedstool

Dit pakket bevat een reproduceerbare inventarisatie en download van openbare
gegevens over zorg, welzijn, gezondheid en leefomgeving op minimaal wijkniveau.
De selectie is uitgevoerd op 10 juli 2026. De ruwe bestanden zijn ongewijzigd
bewaard, met de metadata van de bron ernaast.

## Wat staat waar?

- `raw/`: gedownloade bronbestanden en officiële metadata. Deze map is de
  onveranderlijke bronlaag; bewerk bestanden hierin niet handmatig.
- `DATA_CATALOGUS.md`: inhoud, kwaliteit, beperkingen, licenties en
  toepassingsadvies per bron.
- `indicator_catalog.csv`: doorzoekbare lijst van 1.229 indicator- en
  beschrijvingsvelden uit de opgenomen bronnen, met eenheid en definitie voor
  zover de bron die geeft.
- `sources_reviewed.csv`: alle onderzochte bronhouders, ook als geen bulkbestand
  is opgenomen, met de reden voor opname of uitsluiting.
- `technical_summary.json`: tellingen van rijen, kolommen, perioden,
  gebiedsniveaus en Amsterdam-dekking.
- `manifest.json`: bestandsgrootte, wijzigingsdatum en SHA-256 per bronbestand.
- `checksums.sha256`: controlebestand om te zien of een download later is
  gewijzigd.
- `download_sources.py`: reproduceert de downloads.
- `analyze_sources.py`: bouwt catalogus, samenvatting, manifest en checksums.

## Omvang en dekking

De map `raw/` bevat 106 bestanden, samen circa 1,09 GB (1,01 GiB). De belangrijkste
downloadbestanden bevatten:

| Bron | Rijen | Gebiedsniveau | Periode |
|---|---:|---|---|
| RIVM Beweegvriendelijke omgeving | 18.310 | gemeente, wijk, buurt | 2024 |
| RIVM Gezondheid per wijk en buurt | 91.550 | gemeente, wijk, buurt | 2012-2024 (5 meetjaren) |
| RIVM Regiobeeld | 549.300 | gemeente, wijk, buurt | 2014-2023 |
| CBS SES-WOA | 203.434 | gemeente, wijk, buurt | 2014-2024 |
| CBS Nabijheid voorzieningen | 18.495 | gemeente, wijk, buurt | 2025 |
| CBS Sociaal domein | 209.160 | gemeente en wijk | 2024 |
| CBS Wmo naar type | 26.355 | gemeente en wijk | 2025 |
| CBS Jeugdzorg | 22.596 | land, gemeente en wijk | 2025 |
| Vektis Gemeentezorgspiegel Wmo | 1.653.680 | land, regio, gemeente, wijk, buurt | 2019-2024 |
| Amsterdam O&S BBGA | 7.568.231 | Amsterdamse gebiedsniveaus | 2001-2055, inclusief prognoses |
| Leefbaarometer | 789.455 in uitgepakte tabellen | gemeente, wijk, buurt | 2002-2024 |
| Amsterdam maatschappelijke voorzieningen | 1.771 locaties | punt, koppelbaar aan buurt/wijk/GGW | actuele snapshot |
| Amsterdam sportvoorzieningen | 3.552 objecten/locaties | punt, lijn en vlak | actuele snapshot |
| Amsterdam schoolgebouwen | 50.000+ tabelrijen | adres, wijk, stadsdeel | actuele snapshot |
| Amsterdam woningbouwplannen | 987 plannen | buurt, wijk, GGW, stadsdeel | actuele snapshot |
| Amsterdam gebiedsgrenzen | 518 buurten, 110 wijken, 25 GGW-gebieden | buurt, wijk, GGW, stadsdeel | actuele snapshot |
| Amsterdam O&S focusgebieden en veiligheidsindex | 6 werkboeken | focusgebied / veiligheidsdeelgebied | juni 2026 / 2026-1 |

Rijtellingen bij bestanden met meerdere dimensies zijn geen aantallen unieke
gebieden. Zie `technical_summary.json` voor de uitsplitsing.

## Downloads vernieuwen

Gebruik de gebundelde Python-runtime of Python 3.11+:

```powershell
python .\external-data\download_sources.py
python .\external-data\analyze_sources.py
```

Bestaande downloads worden standaard overgeslagen. Gebruik `--force` alleen als
een bewuste nieuwe snapshot gewenst is. Met `--skip-large` wordt het grote
Leefbaarometer-archief overgeslagen. Na een nieuwe download moeten de datum en
inhoud in `DATA_CATALOGUS.md` worden herzien; brondefinities kunnen veranderen.

## Belangrijk vóór koppeling aan de tool

1. Koppel op gebiedscode én indelingsjaar, nooit alleen op gebiedsnaam.
2. Toon wijkcijfers niet alsof het buurtcijfers zijn.
3. Label gemodelleerde schattingen, registraties, voorlopige cijfers en
   prognoses zichtbaar verschillend.
4. Bereken percentages en tarieven met hun noemer; neem geen ongewogen
   gemiddelde van buurten.
5. Houd ontbrekend, onderdrukt, afgerond en werkelijk nul als verschillende
   toestanden.
6. Controleer de licentie en vereiste bronvermelding opnieuw bij publicatie.
7. Behandel aanbod- en infrastructuurkaarten als locatiecontext, niet als maat
   voor capaciteit, kwaliteit of daadwerkelijk gebruik.

De inhoudelijke en technische uitwerking staat in
[`DATA_CATALOGUS.md`](DATA_CATALOGUS.md).
