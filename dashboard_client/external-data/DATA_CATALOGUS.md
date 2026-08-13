# Datacatalogus zorg, welzijn en gezondheid

## Doel en selectie

Deze inventarisatie zoekt aanvullingen voor de Dynamo-gebiedstool die helpen bij
de vraag waar voorzieningen in Amsterdam-Oost het meeste maatschappelijk nut
kunnen hebben. Een bron is als download opgenomen wanneer deze:

- gegevens op CBS-buurt- of wijkniveau bevat, of specifiek de fijnmazige
  Amsterdamse gebiedsindeling gebruikt;
- landelijk vergelijkbaar is of voor Amsterdam unieke inhoud toevoegt;
- zonder individuele persoonsgegevens als openbaar bestand/API beschikbaar is;
- inhoudelijk bruikbaar is voor gezondheid, welzijn, participatie,
  bestaanszekerheid, jeugd, Wmo, zorggebruik, bereikbaarheid of leefomgeving.

Dit is een brede, praktische inventarisatie van relevante officiële bronnen,
niet de claim dat iedere Nederlandse website of ieder onderzoeksbestand is
gevonden. Bronnen zonder stabiele bulkdownload of zonder minimaal wijkniveau
zijn wel vastgelegd in `sources_reviewed.csv`.

## Aanbevolen volgorde van toevoegen

### Prioriteit A — direct bruikbaar voor de gebiedskeuze

1. **RIVM Gezondheid per wijk en buurt**: behoefte-indicatoren voor onder meer
   eenzaamheid, mentale gezondheid, stress, kwetsbaarheid, beperkingen,
   mantelzorg, bewegen, middelengebruik en ervaren leefomgeving.
2. **CBS Sociaal domein, Wmo en Jeugdzorg**: daadwerkelijk geregistreerd gebruik
   van ondersteuning. Deze drie bronnen zijn alleen op wijkniveau beschikbaar.
3. **Vektis Gemeentezorgspiegel Wmo**: unieke Wmo-reeks 2019-2024 op
   buurtniveau, inclusief leeftijdsgroepen en maatwerkarrangementen.
4. **CBS Nabijheid voorzieningen**: bereikbaarheid van huisarts, huisartsenpost,
   apotheek, ziekenhuis, fysiotherapie, consultatiebureau, kinderopvang,
   scholen, winkels, groen, sport, OV en bibliotheek.
5. **RIVM Beweegvriendelijke Omgeving**: fysiek potentieel voor bewegen via
   groen/blauw, sportaccommodaties, speelplekken en nabijheid van voorzieningen.
6. **Amsterdam O&S BBGA**: de breedste Amsterdam-specifieke aanvulling, met
   gemeentelijke gebiedsniveaus, definities en lokale indicatoren.

### Prioriteit B — waardevol als verklarende of vergelijkende context

7. **RIVM Regiobeeld**: zorgkosten en aantallen patiënten per zorgsector,
   afgeleid van Vektis-data, plus SES-context op wijk en buurt.
8. **CBS SES-WOA**: totale sociaal-economische score en componenten welvaart,
   opleiding en arbeidsverleden, inclusief betrouwbaarheidsinformatie.
9. **Leefbaarometer**: samengestelde leefbaarheid en dimensies fysiek,
   onveiligheid, sociaal, voorzieningen en woningvoorraad.

Gebruik SES, Leefbaarometer en verschillende afgeleide achterstandsindicatoren
niet tegelijk als onafhankelijke bewijzen voor dezelfde behoefte. Dat zou
dezelfde onderliggende factoren dubbel wegen.

## Opgenomen bronnen

### 1. RIVM — Beweegvriendelijke omgeving, 50143NED

- **Bestand:** `raw/rivm_beweegvriendelijke_omgeving_50143NED/data.csv`.
- **Bron:** [RIVM-dataset op data.overheid.nl](https://data.overheid.nl/dataset/c4910fc1-263e-40d6-948b-acc80d885848) en [OData-service](https://dataderden.cbs.nl/ODataApi/OData/50143NED).
- **Dekking:** Nederland, gemeente, wijk en buurt; verslagjaar 2024.
- **Inhoud:** totaalscore 0-100 en vier deelindicatoren: recreatief groen en
  blauw, sportaccommodaties, sport- en speelplekken en nabijheid van
  voorzieningen.
- **Let op:** de score beschrijft mogelijkheden in de fysieke omgeving, niet het
  feitelijke beweeggedrag. De methodiek is in 2020 vernieuwd; oudere en nieuwere
  reeksen zijn niet zonder meer vergelijkbaar.
- **Licentie:** CC BY 4.0; bronvermelding RIVM/CBS opnemen.

### 2. RIVM — Gezondheid per wijk en buurt, 50150NED

- **Bestand:** `raw/rivm_gezondheid_wijk_buurt_50150NED/data.csv`
- **Officiële metadata:** naast het bestand in `metadata/*.json`.
- **Bron:** [RIVM-dataset op data.overheid.nl](https://data.overheid.nl/dataset/70128-gezondheid-per-wijk-en-buurt--2012-2016-2020-2022-2024--indeling-2024-) en [OData-service](https://dataderden.cbs.nl/ODataApi/OData/50150NED).
- **Dekking:** Nederland, gemeente, wijk en buurt; gebiedsindeling 2024;
  meetjaren 2012, 2016, 2020, 2022 en 2024.
- **Downloadselectie:** 18 jaar en ouder, centrale schatting; 91.550 rijen,
  60 onderwerpvelden (inclusief gebiedskenmerken). Leeftijdsgroepen en
  95%-intervallen zijn niet in `data.csv`
  opgenomen, maar hun categorieën staan in de metadata en zijn via dezelfde API
  later reproduceerbaar.
- **Inhoud:** ervaren gezondheid, chronische aandoeningen, gehoor/zicht/bewegen,
  valincidenten, angst/depressie, suïcidegedachten, stress, kwetsbaarheid,
  veerkracht, regie, eenzaamheid, sociale steun, mantelzorg, vrijwilligerswerk,
  moeite rondkomen, gewicht, roken, alcohol, bewegen, sporten, actief vervoer,
  geluidshinder, slaapverstoring, woon- en buurttevredenheid, groen en verkoeling.
- **Methode:** grotendeels kleine-gebiedsschattingen op basis van
  Gezondheidsmonitoren en modellen. Een buurtwaarde is dus niet hetzelfde als
  een rechtstreeks gemeten buurtenquête. Toon daarom `gemodelleerde schatting`
  en bied waar relevant het interval aan.
- **Licentie:** CC BY 4.0; bronvermelding RIVM/CBS opnemen.

### 3. RIVM — Regiobeeld wijk en buurt, 50149NED

- **Bestand:** `raw/rivm_regiobeeld_wijk_buurt_50149NED/data.csv`.
- **Bron:** [OData-service](https://dataderden.cbs.nl/ODataApi/OData/50149NED).
- **Dekking:** gemeente, wijk en buurt volgens indeling 2024; 2014-2023;
  549.300 rijen en 27 onderwerpen.
- **Inhoud:** zorgkosten en aantallen patiënten voor onder meer totaal zorg,
  farmacie, geboortezorg, ggz, huisartsenzorg, hulpmiddelen, mondzorg,
  multidisciplinaire zorg, paramedische zorg, verpleging/verzorging en medisch-
  specialistische zorg. Bevat ook SES-context.
- **Herkomst:** Vektis-data zijn via CBS Remote Access verwerkt voor het RIVM.
- **Let op:** `aantal`, `per 10.000` en `score` zijn verschillende cijfersoorten.
  Meng of som deze niet. Kosten en gebruik zeggen iets anders dan onvervulde
  behoefte; hoge kosten zijn niet automatisch een vestigingsadvies.
- **Licentie:** CC BY 4.0 volgens de publicatievoorwaarden van de tabel.

### 4. CBS — SES-WOA, 86296NED

- **Bestand:** `raw/cbs_ses_woa_86296NED/data.csv`.
- **Bron:** [CBS StatLine](https://www.cbs.nl/nl-nl/cijfers/detail/86296NED) en
  [OData-service](https://opendata.cbs.nl/ODataApi/OData/86296NED).
- **Dekking:** gemeente, wijk en buurt volgens indeling 2025; 2014-2024;
  203.434 rijen en 43 onderwerpen.
- **Inhoud:** SES-WOA totaalscore, componenten financiële welvaart,
  opleidingsniveau en recent arbeidsverleden, relatieve posities en
  betrouwbaarheidsgrenzen.
- **Let op:** 2024 kan voorlopig zijn. Een relatieve score is geen percentage en
  niet geschikt om zonder uitleg als absoluut tekort te presenteren. Gebruik
  bij kleine gebieden de betrouwbaarheidsinformatie.
- **Licentie:** CC BY 4.0; bron CBS.

### 5. CBS — Nabijheid voorzieningen, 86270NED

- **Bestand:** `raw/cbs_nabijheid_voorzieningen_86270NED/data.csv`.
- **Bron:** [CBS StatLine](https://www.cbs.nl/nl-nl/cijfers/detail/86270NED) en
  [OData-service](https://opendata.cbs.nl/ODataApi/OData/86270NED).
- **Dekking:** gemeente, wijk en buurt volgens indeling 2025; verslagjaar 2025;
  18.495 gebieden en 114 onderwerpen.
- **Inhoud:** afstanden tot en aantallen binnen afstandsgrenzen van zorg,
  onderwijs, kinderopvang, detailhandel, horeca, groen, sport, OV en cultuur.
- **Let op:** afstand is doorgaans berekend over de weg vanaf bewoonde adressen
  en is geen reistijd of toegankelijkheid voor mensen met een beperking.
  Controleer per variabele de definitie in `metadata/MeasureCodes.json`.
- **Licentie:** CC BY 4.0; bron CBS.

### 6. CBS — Gebruik voorzieningen sociaal domein, 85994NED

- **Bestand:** `raw/cbs_sociaal_domein_85994NED/data.csv`.
- **Bron:** [CBS StatLine](https://www.cbs.nl/nl-nl/cijfers/detail/85994NED) en
  [OData-service](https://opendata.cbs.nl/ODataApi/OData/85994NED).
- **Dekking:** gemeente en wijk; definitieve jaarcijfers 2024; 209.160 rijen.
- **Inhoud:** personen en huishoudens naar aantal en combinatie van
  voorzieningen uit Wmo, Jeugdwet en Participatiewet.
- **Let op:** veel rijen zijn combinaties van dimensies en dus niet optelbaar.
  Koppel de sleutelvelden aan alle officiële codelijsten in `metadata/`.
  Door onderdrukking of afronding kan een lege waarde geen nul betekenen.
- **Licentie:** CC BY 4.0; bron CBS.

### 7. CBS — Wmo-cliënten naar type, 86158NED

- **Bestand:** `raw/cbs_wmo_type_86158NED/data.csv`.
- **Bron:** [CBS StatLine](https://www.cbs.nl/nl-nl/cijfers/detail/86158NED) en
  [OData-service](https://opendata.cbs.nl/ODataApi/OData/86158NED).
- **Dekking:** gemeente en wijk; voorlopige jaarcijfers 2025; 26.355 rijen.
- **Inhoud:** Wmo-cliënten en maatwerkvoorzieningen naar type, absoluut en/of
  relatief zoals in de metadata omschreven.
- **Let op:** registratiegebruik is mede afhankelijk van toegang, beleid en
  administratieve praktijk. Het meet geen latente vraag. Toon het kenmerk
  `voorlopig`.
- **Licentie:** CC BY 4.0; bron CBS.

### 8. CBS — Jeugdzorg in natura, 86204NED

- **Bestand:** `raw/cbs_jeugdzorg_wijken_86204NED/data.csv`.
- **Bron:** [CBS StatLine](https://www.cbs.nl/nl-nl/cijfers/detail/86204NED) en
  [OData-service](https://opendata.cbs.nl/ODataApi/OData/86204NED).
- **Dekking:** land, gemeente en wijk; voorlopige jaarcijfers 2025; 22.596
  rijen en 21 meetvelden.
- **Inhoud:** jongeren en trajecten naar jeugdzorgvorm, leeftijd,
  huishoudsituatie en verwijzer.
- **Let op:** dimensiecombinaties overlappen; niet optellen zonder de
  populatiedefinitie te controleren. Kleine aantallen kunnen zijn afgerond of
  onderdrukt. Alleen wijkniveau tonen.
- **Licentie:** CC BY 4.0; bron CBS.

### 9. Vektis — Gemeentezorgspiegel Wmo-publicatie 2025

- **Bestanden:** vier Excelbestanden in `raw/vektis_gemeentezorgspiegel/`:
  buurt alle leeftijden (248.019 rijen), buurt naar leeftijd (772.026), wijk/
  gemeente/regio/land (633.635) en een documentatiewerkboek.
- **Bron:** [Vektis Gemeentezorgspiegel — beschikbare data](https://www.vektis.nl/gemeentezorgspiegel/data).
- **Dekking:** 2019-2024; CBS-wijk- en buurtindeling 2024; land, VNG/ZN-regio,
  gemeente, wijk en buurt. Amsterdam heeft eigen buurt-, wijk- en regiorijen.
- **Leeftijd:** alle leeftijden en de groepen 0-17, 18-23, 18-64, 24-64, 65+,
  65-74, 75-84 en 85+.
- **Inhoud:** unieke Wmo-cliënten voor hulp bij het huishouden, hulpmiddelen en
  diensten, begeleiding, dagbesteding, ondersteuning thuis totaal, overige
  arrangementen, beschermd wonen, verblijf en opvang en totaal zorgdomein
  exclusief verblijf/opvang.
- **Herkomst:** eigen berekeningen van Vektis in de CBS-microdata-omgeving,
  projectnummer 3132; onderzoek uitgevoerd in juli 2025.
- **Privacy:** categorieën met minder dan 10 cliënten zijn niet beschikbaar;
  gepubliceerde aantallen zijn afgerond op tientallen. Ongeveer 3% van de
  Wmo-gebruikers kon volgens de toelichting niet aan een gebied worden
  toegewezen omdat de woonplaats op peildatum 30 juni niet bekend was.
- **Definitie:** `Totaal zorgdomein` telt unieke Wmo-cliënten met een
  maatwerkvoorziening, met uitzondering van verblijf en opvang. Leeftijd en
  woonlocatie worden op 30 juni bepaald.
- **Overlap:** deze reeks is fijner en langer dan CBS 86158NED, maar definities
  en publicatiemoment verschillen. Toon ze niet als één doorlopende reeks zonder
  bron- en definitiecontrole.
- **Licentie:** de bestanden zijn publiek downloadbaar en dragen copyright
  Vektis. Een expliciete open licentie is niet in het documentatiewerkboek
  aangetroffen. Stem externe herpublicatie en bronvermelding daarom met Vektis
  af voordat de gegevens in een publieke servertool worden ingebouwd.

### 10. Amsterdam O&S — Basisbestand Gebieden Amsterdam (BBGA)

- **Bestanden:** `raw/amsterdam_bbga/bbga-latest-and-greatest.csv`, `.xlsx`,
  `metadata-latest-and-greatest.csv` en `bbga-std-latest-and-greatest.csv`.
- **Bron:** [O&S Amsterdam](https://onderzoek.amsterdam.nl/dataset/basisbestand-gebieden-amsterdam-bbga).
- **Dekking:** Amsterdam op meerdere gemeentelijke gebiedsniveaus, waaronder
  stadsdelen, 25 gebieden, wijken en buurten; 918 variabelen en 7.568.231
  rijen in lang formaat.
- **Inhoud:** bevolking, huishoudens, inkomen, armoede, werk, participatie,
  onderwijs, jeugd, zorg/welzijn, veiligheid, wonen, openbare ruimte en
  prognoses. De metadata-CSV bevat definities, eenheden, bron en beschikbaarheid.
- **Let op:** het bereik 2001-2055 bevat historische cijfers én prognoses; niet
  iedere indicator bestaat voor ieder jaar. Gebiedsgrenzen veranderden, onder
  meer rond Weesp en de Amsterdamse herindeling. Sommige kleine waarden en hoge
  percentages zijn vanwege privacy afgerond. Volg altijd de variabelemetadata.
- **Licentie:** de dataset is openbaar aangeboden; de downloadpagina legt in de
  opgehaalde bestanden geen eenduidige licentietekst vast. Leg vóór externe
  herpublicatie de actuele Amsterdamse gebruiksvoorwaarden en bronvermelding
  vast in de applicatie.
- **Sinds aug. 2026 deels geïntegreerd:** de prognosevariabelen `BEV_PROG` en
  `BEV65PLUS_PROG` (jaarlijks 2027–2055) worden gebruikt in het tabblad
  *Vooruitblik*, voor **heel Amsterdam** (gemeente, elk stadsdeel, elk gebied,
  elke wijk — geen buurtniveau). Dit is sinds aug. 2026 de **enige**
  prognosebron in dat tabblad: het eigen trendmodel is verwijderd, dus waar
  BBGA (en, alleen voor Oost, bron 19) geen waarde heeft, toont de tool
  expliciet geen prognose i.p.v. een geschat getal. De overige 916 variabelen
  zijn nog steeds alleen catalogus-context.

### 11. BZK — Leefbaarometer 3.0, meting 2024

- **Bestand:** `raw/leefbaarometer_2024/open-data-leefbaarometer-meting-2024.zip`;
  relevante gemeente-, wijk- en buurttabellen zijn ook uitgepakt onder
  `uitgepakt_relevant/`.
- **Bron:** [Leefbaarometer open data](https://www.leefbaarometer.nl/page/Opendata).
- **Dekking:** gemeente, wijk en buurt; scores voor 2002, 2008, 2012, 2014,
  2016, 2018, 2020, 2022 en 2024; daarnaast ontwikkeling tussen meetjaren.
- **Inhoud:** totale leefbaarheid, afwijking en dimensies fysieke omgeving,
  onveiligheid, sociale samenhang, voorzieningen en woningvoorraad.
- **Let op:** dit is een samengesteld model, geen directe meting van gezondheid
  of zorgvraag. Gebruik het als context, niet als causale verklaring. De
  ontwikkelingstabellen bevatten jaarparen en zijn niet zonder meer een gewone
  tijdreeks.
- **Licentie:** CC0 volgens de open-datapagina.

### 12. Gemeente Amsterdam — Maatschappelijke voorzieningen

- **Bestanden:** `raw/amsterdam_maatschappelijke_voorzieningen/voorzieningen_op_de_kaart.csv`
  en `.geojson`.
- **Bron:** [Data Amsterdam: maatschappelijke voorzieningen](https://api.data.amsterdam.nl/v1/docs/datasets/maatschappelijke_voorzieningen.html).
- **Dekking:** actuele momentopname van gemeentelijke voorzieningen; puntlocaties
  met naam, domein, categorie, soort, adres, postcode en stadsdeel.
- **Inhoud:** ruimtelijke aanbodlaag voor zorg, welzijn, ontmoeting, sport en
  aanverwante maatschappelijke functies. De GeoJSON is geschikt voor kaart,
  tellen per buurt en afstandsanalyses.
- **Let op:** dit is een gemeentelijke voorzieningeninventaris, geen volledige
  sociale kaart van alle onafhankelijke zorg- en welzijnsaanbieders. Een punt
  zegt evenmin iets over capaciteit, wachttijd, toegankelijkheid of feitelijk
  gebruik. Verrijk deze laag eerst met beheer- en actualiteitsinformatie voordat
  hij als aanbodregister wordt getoond.
- **Licentie:** publiek volgens de API-documentatie; controleer actuele
  gemeentelijke gebruiksvoorwaarden en bronvermelding bij publicatie.

### 13. Gemeente Amsterdam — Sportvoorzieningen

- **Bestanden:** acht GeoJSON-lagen onder `raw/amsterdam_sportvoorzieningen/`:
  aanbieders, gymzalen, hallen, hardlooproutes, openbare sportplekken, parken,
  velden en zwembaden.
- **Bron:** [Data Amsterdam: sport](https://api.data.amsterdam.nl/v1/docs/datasets/sport.html).
- **Dekking:** actuele object- en locatielagen voor heel Amsterdam, met punt-,
  lijn- en vlakgeometrieën.
- **Inhoud:** input voor bereikbaarheid, beweegvriendelijke omgeving, informele
  ontmoeting en locatiekeuze. Analyseer per buurt zowel aantallen als afstand
  en, waar mogelijk, oppervlakte.
- **Let op:** tel geen objecttypen door elkaar op als één aanbodmaat. Een park,
  sportveld en aanbieder zijn verschillende analyseenheden; aanbieders kunnen
  ook op een al getelde locatie actief zijn. De laag bevat geen deelname,
  tarieven of openingsuren.
- **Licentie:** publiek volgens de API-documentatie; actuele voorwaarden bij
  herpublicatie controleren.

### 14. Gemeente Amsterdam — Schoolgebouwen en kengetallen

- **Bestanden:** `accommodatie.csv`, `instelling.csv`, `kengetallen.csv`,
  `gebruik.csv` en `object.csv` in `raw/amsterdam_schoolgebouwen/`.
- **Bron:** [Data Amsterdam: schoolgebouwen](https://api.data.amsterdam.nl/v1/docs/datasets/schoolgebouwen.html).
- **Dekking:** actuele momentopname; accommodaties zijn adresseerbaar en de
  tabellen zijn via accommodatie-, instelling- en object-id aan elkaar te
  koppelen.
- **Inhoud:** schooltype, gebouwkenmerken, gebruik, leerlingaantallen,
  prognoses, ruimtebehoefte en achterstandsscore. Dit geeft een vroeg signaal
  voor jeugd- en gezinsvraag en voor multifunctioneel gebruik van voorzieningen.
- **Let op:** de bestandstabellen zijn genormaliseerd. Maak eerst een
  gedocumenteerde join en voorkom dubbeltelling van instellingen die meerdere
  objecten of accommodaties gebruiken. Leerlingprognose is geen directe
  zorgvraag.
- **Licentie:** publiek volgens de API-documentatie; actuele voorwaarden bij
  herpublicatie controleren.

### 15. Gemeente Amsterdam — Openbare woningbouwplannen

- **Bestanden:** `woningbouwplannen_openbaar.csv` en `.geojson` in
  `raw/amsterdam_nieuwbouwplannen/`.
- **Bron:** [Data Amsterdam: nieuwbouwplannen](https://api.data.amsterdam.nl/v1/docs/datasets/nieuwbouwplannen.html).
- **Dekking:** publieke momentopname van planlocaties met buurt-, wijk-,
  GGW-gebied- en stadsdeelcodes, planfase en woningsegmenten.
- **Inhoud:** aantallen (geplande) woningen, onder meer sociale huur,
  middensegment, jongeren- en studentenwoningen; bruikbaar als scenario-input
  voor toekomstige bewoners en voorzieningenbehoefte.
- **Let op:** plannen kunnen wijzigen, vertragen of vervallen. Gebruik daarom
  planfase en verwachte start/oplevering als scenario, niet als gerealiseerde
  bevolking. Koppel niet zonder controle aan een bevolkingsprognose: beide
  kunnen dezelfde toekomstige ontwikkeling weerspiegelen.
- **Licentie:** Creative Commons Naamsvermelding volgens de API-documentatie.

### 16. Gemeente Amsterdam — Officiële gebiedsindelingen

- **Bestanden:** actuele GeoJSON-grenzen voor `buurten`, `wijken`,
  `ggwgebieden` en `stadsdelen` in `raw/amsterdam_gebieden/`.
- **Bron:** [Data Amsterdam: gebieden](https://api.data.amsterdam.nl/v1/docs/datasets/gebieden.html).
- **Dekking:** heel Amsterdam; de GGW-laag bevat de 25 Amsterdamse gebieden.
- **Toepassing:** dit is de leidende kaart- en keuzelaag voor buurt, wijk,
  stadsdeel en de 25 gebieden. Bewaar de gedownloade snapshot met het bronmoment
  en koppel statistieken op de expliciete code, niet op naam of geometrische
  overlap alleen.
- **Let op:** administratieve grenzen kunnen wijzigen. De actuele grenslaag is
  niet automatisch passend bij historische CBS- of BBGA-cijfers; gebruik voor
  tijdreeksen het indelingsjaar van de indicator en toon een grenswaarschuwing.
- **Licentie:** publiek volgens de API-documentatie; actuele voorwaarden bij
  herpublicatie controleren.

### 17. Amsterdam O&S — Outcomemonitor focusgebieden

- **Bestanden:** vier Excelbestanden in `raw/amsterdam_ois_focusgebieden/`: een
  indicatorenoverzicht en volledige tabellen voor Masterplan Zuidoost, Aanpak
  Noord en Samen Nieuw-West (juni 2026).
- **Bron:** [O&S Amsterdam: focusgebieden](https://onderzoek.amsterdam.nl/dataset/focusgebieden-amsterdam).
- **Inhoud:** thema's omvatten onder meer inclusie en participatie, jeugd,
  bestaanszekerheid en sociale ontwikkeling. De werkboeken bevatten meerdere
  tabbladen en verschillende meetmomenten.
- **Gebruik:** alleen als leer- en benchmarkbron voor gerichte
  gebiedsprogramma's. Niet als buurtbenchmark voor Amsterdam-Oost: Oost valt
  niet onder deze drie focusgebiedprogramma's en indicatorselecties zijn
  programmatisch specifiek.
- **Licentie:** openbare O&S-download; leg hergebruik en bronvermelding vast
  vóór externe publicatie.

### 18. Amsterdam O&S — Veiligheidsindex 2026-1

- **Bestanden:** `veiligheidsindex_2026_1.xlsx` en
  `veiligheidsindex_vergelijking_2026_1.xlsx` in
  `raw/amsterdam_ois_veiligheidsindex/`.
- **Bron:** [O&S Amsterdam: openbare orde en veiligheid](https://onderzoek.amsterdam.nl/dataset/openbare-orde-en-veiligheid).
- **Dekking:** veiligheidsmonitorgebieden/deelgebieden, met meerdere jaren en
  vergelijkingsmogelijkheden; de werkboeken bevatten respectievelijk zes
  tabbladen.
- **Inhoud:** geregistreerde criminaliteit en samengestelde
  veiligheidsindicatoren. Het vergelijkingsbestand heeft een gebruikersselectie
  en historische tabbladen.
- **Let op:** veiligheid is relevante leefomgevingscontext, maar geen directe
  maat voor gezondheid, zorgvraag of kwaliteit van welzijnsaanbod. Doorbreek
  niets naar een buurtlager niveau dan de bron ondersteunt en label
  registraties/indices zichtbaar.
- **Licentie:** openbare O&S-download; leg hergebruik en bronvermelding vast
  vóór externe publicatie.

### 19. Amsterdam O&S — Bevolkingsprognose 2026, stadsdeel/wijken Oost

- **Bestand:** `2026_bevolkingsprognose_stadsdeel_wijken_M_Oost.xlsx` in
  `raw/amsterdam_ois_bevolkingsprognose_oost/` — één werkblad per wijk (`MA`–`MQ`)
  plus stadsdeel Oost totaal, 5-jaars leeftijdsklassen, 2026/2030/2035/2040/2050/2055.
- **Bron:** Amsterdam O&S/afdeling Ruimte en Duurzaamheid (aangeleverd door de
  gebruiker, aug. 2026; niet via een open-datapagina gedownload).
- **Status: geïntegreerd** (in tegenstelling tot de meeste bronnen hierboven, die
  alleen catalogus-context zijn). Vervangt, samen met de al aanwezige **BBGA**
  (§10, variabelen `BEV_PROG`/`BEV65PLUS_PROG`, sinds aug. 2026 citywide
  ingezet), het volledig verwijderde eigen trendmodel in het tabblad
  *Vooruitblik*. Dit specifieke bestand dekt alleen `a_00_14`/`a_15_24`/
  `a_45_64`, en alleen voor stadsdeel Oost en zijn 15 wijken — het bevat geen
  andere geografie. Zie `docs/VOORUITBLIK-TEAM.md` §4 voor de volledige
  verantwoording en `data-prep/official_forecast.py` voor de parser.
- **Let op:** geen onzekerheidsinterval in de bron; geen buurt- of gebiedsniveau;
  geen huishouden-/alleenwonend-variabele. Waar geen van beide bronnen een
  waarde heeft, toont Vooruitblik expliciet geen prognose — er is geen
  eigen model meer dat de rest van de gemeente of de ontbrekende doelgroepen
  opvangt.
- **Licentie:** aangeleverd door de gebruiker; herpublicatie-voorwaarden bij O&S
  navragen vóór extern gebruik.

## Bekeken bronnen die niet als databestand zijn opgenomen

### GGD Amsterdam — Gezondheid in Beeld

Het dashboard bevat lokaal zeer relevante thema's zoals fysieke en mentale
gezondheid, zorggebruik, eenzaamheid, mantelzorg, bestaanszekerheid, leefstijl,
middelengebruik en jeugd. De cijfers zijn per grafiek als CSV/Excel te
exporteren, maar tijdens deze inventarisatie was geen stabiele, gedocumenteerde
bulk-API beschikbaar. Automatisch klikken en honderden losse exports zou niet
reproduceerbaar genoeg zijn. De gebruikershandleiding is wel opgenomen in
`raw/bron_documentatie/`. Zie [Gezondheid in Beeld](https://ggdgezondheidinbeeld.nl/mosaic/)
en de [datasetregistratie](https://data.overheid.nl/dataset/mairbhcp_xlteg).

De eerder gepubliceerde technische verwijzing naar een afzonderlijke
`amsterdam.ggdgezondheidinbeeld.nl`-openAPI leverde tijdens de hercontrole geen
bruikbaar, stabiel bulkcontract op. Houd daarom de dashboardexport als
handmatige bronroute totdat GGD Amsterdam een versieerbare bulkdownload of API
publiceert.

**Advies:** bouw later een expliciete GGD-connector zodra GGD Amsterdam een
bulkexport of API-contract kan leveren; dit is vooral waardevol voor jeugd en
Amsterdam-specifieke monitorvariabelen die RIVM 50150 niet bevat.

### Nivel Zorgregistraties Eerste Lijn

Nivel heeft inhoudelijk rijke registraties van huisartsenzorg en andere
eerstelijnszorg, maar gedetailleerde micro- en klein-gebiedsdata zijn niet als
open bulkbestand op wijk/buurt beschikbaar. Gebruik vraagt een aanvraag en
voorwaarden. Daarom is niets gedownload. Zie
[Nivel Zorgregistraties Eerste Lijn](https://www.nivel.nl/nl/panels-en-registraties/nivel-zorgregistraties-eerste-lijn).

### Vektis open data

De reguliere open-databestanden van Vektis gebruiken vooral gemeente of
postcode-3 en voldoen daardoor niet aan het gekozen minimum van CBS-wijkniveau.
De gebruiksvoorwaarden zijn bovendien beperkter dan een open licentie. De
bijsluiter is ter referentie opgenomen in `raw/bron_documentatie/`. De RIVM-
tabel 50149NED levert al Vektis-afgeleide zorgcijfers op wijk en buurt. Zie
[Vektis open data](https://www.vektis.nl/open-data).

De afzonderlijke Wmo-publicatie van de publieke Gemeentezorgspiegel is wel
opgenomen. Aanvullende dashboards over Zvw, Wlz, ggz, ouderen en leefstijl zijn
interactief beschikbaar, maar daarvoor is nog geen gelijkwaardig publiek
bulkbestand met helder hergebruikskader vastgesteld.

### Atlas Leefomgeving / Nationaal Georegister

Luchtkwaliteit, geluid, hitte, groen en milieugezondheidslagen zijn relevant,
maar worden vooral als raster, kaartlaag of WFS aangeboden en zijn niet altijd
vooraf geaggregeerd tot CBS-wijk/buurt. Opname vereist een aparte GIS-pijplijn
met oppervlakte- of bevolkingsgewogen aggregatie. Dit is een zinvolle tweede
fase, geen plug-and-play tabelimport.

### RIVM Gezondheidsmonitor — onderliggende data

De open klein-gebiedsschattingen uit 50150NED zijn opgenomen. De onderliggende
respondentdata en bepaalde tabellen vragen een aanvraag en zijn niet als vrij
bulkbestand toegevoegd. Gebruik nooit microdata in de publiek draaiende tool.

### Waarstaatjegemeente en vergelijkbare portalen

Deze portalen zijn bekeken als vindplaats, maar veel indicatoren herpubliceren
CBS-, RIVM- of gemeentelijke brondata. Duplicaten zijn niet nogmaals gedownload;
de primaire bron heeft voorrang vanwege definities, versiebeheer en licentie.

## Koppeling aan Dynamo-dienstverlening

| Ondersteuningsvorm | Bruikbare indicatorgroepen |
|---|---|
| Buurtwerk en ontmoeting | eenzaamheid, sociale steun, vrijwilligerswerk, regie, Leefbaarometer sociaal, BBGA participatie |
| Mantelzorg en informele hulp | mantelzorg geven, kwetsbaarheid, beperkingen, Wmo, nabijheid zorg en ontmoeting |
| Ouderenondersteuning | vallen, mobiliteitsbeperking, kwetsbaarheid, Wmo-type, huisarts/apotheek/fysiotherapie |
| Armoede en bestaanszekerheid | moeite rondkomen, SES-WOA, Participatiewet-combinaties, BBGA inkomen/armoede |
| Jeugd en gezin | jeugdzorgvorm, leeftijd, verwijzer, BBGA jeugd/onderwijs, later GGD-jeugdmonitor |
| Gezonde leefstijl | bewegen, sport, roken, alcohol, gewicht, groen, sportvoorzieningen en actieve verplaatsing |
| Mentale gezondheid | angst/depressie, stress, suïcidegedachten, eenzaamheid, zorggebruik ggz |
| Toegang en locatiekeuze | afstanden tot zorg, OV, scholen, kinderopvang, winkels, groen en sport; combineer met doelgroepomvang |

Een indicator beschrijft een gebied en bewijst geen individuele behoefte. Maak
geen risicoprofielen van personen en gebruik herkomst of gezondheid niet als
proxy voor geschiktheid van individuele bewoners.

## Technisch gegevenscontract voor de tool

Normaliseer ingelezen data naar één intern model, bijvoorbeeld:

```text
source_id, indicator_id, area_code, area_level, boundary_year,
period, value, unit, numerator, denominator, estimate_type,
lower_ci, upper_ci, provisional, suppressed, forecast,
source_url, definition, retrieved_at
```

Aanvullende regels:

- bewaar de originele broncode en leid een stabiele interne indicator-id af;
- scheid observatie, registratie, modelschatting en prognose;
- sla gebiedsgeometrie en grensjaar apart op en onderhoud crosswalks;
- normaliseer niet automatisch de richting: `meer groen` en `meer eenzaamheid`
  hebben tegengestelde betekenis;
- vergelijk alleen dezelfde definitie, eenheid, leeftijdsgroep en indeling;
- bereken Amsterdam- of gemeentereferenties gewogen met de juiste noemer;
- toon betrouwbaarheidsinterval en waarschuwing bij onzekere schattingen;
- leg bron, peildatum, wijzigingsdatum, licentie en selectie in de UI vast;
- laat wijk-only indicatoren uit de buurtkeuze verdwijnen of markeer ze
  expliciet als wijkcontext;
- laad de grote BBGA- en RIVM-bestanden server-side naar Parquet of een database;
  lever ze niet integraal aan de React-client.

## Aannames in deze inventarisatie

1. `Minimaal wijkniveau` betekent CBS-wijk of een aantoonbaar vergelijkbaar
   Amsterdams gebied; postcode-3 en alleen gemeente zijn onvoldoende.
2. Een bron mag wijk én buurt bevatten; voor wijk-only onderwerpen is opname
   toegestaan omdat de gebruiker `minimaal wijkniveau` vroeg.
3. Voor RIVM 50150 is 18+ en de centrale schatting gekozen om de eerste download
   beheersbaar en direct toepasbaar te houden. Leeftijdsgroepen en intervallen
   zijn bewust reproduceerbaar gehouden via metadata en script.
4. Voor zeer dimensionale CBS-tabellen is het meest recente complete jaar
   gekozen: sociaal domein 2024 definitief; Wmo en jeugdzorg 2025 voorlopig.
5. Het bestaande CBS Kerncijfers Wijken en Buurten-bestand in de tool is niet
   gedupliceerd.
6. Primaire bronhouders krijgen voorrang boven dashboards die dezelfde cijfers
   herpubliceren.
7. Openbare beschikbaarheid betekent niet automatisch dat iedere vorm van
   herpublicatie is toegestaan; licenties moeten bij livegang opnieuw worden
   gecontroleerd.
8. De downloads zijn een snapshot van 10 juli 2026; `latest`-bestanden van BBGA
   zijn niet permanent versie-identiek en moeten bij vernieuwing worden
   gearchiveerd met datum.
9. De publieke Vektis-Wmo-bestanden zijn als bronlaag opgenomen vanwege hun
   unieke buurtniveau. Opname in de publieke tool zelf wacht op een expliciete
   hergebruikstoets, omdat in het werkboek wel copyright maar geen open licentie
   staat.
10. Amsterdamse gemeentelijke API-lagen zijn momentopnamen. De tool moet de
    download- en bronversie tonen, periodiek verversen en een eventuele
    toekomstige API-sleutel server-side beheren.
11. Voorzieningen-, sport- en schoollagen beschrijven aanbod of infrastructuur;
    zij zijn geen meting van capaciteit, bereik, kwaliteit, wachttijd of gebruik.
12. De O&S-focusgebiedswerkboeken zijn opgenomen als context en niet als
    algemene Oost-score. Veiligheidsindexgegevens zijn leefomgevingscontext en
    geen proxy voor individuele zorg- of welzijnsbehoefte.

## Kwaliteitscheck en reproduceerbaarheid

`analyze_sources.py` heeft per bestand rijen, kolommen, perioden,
gebiedsniveaus, unieke codes en Amsterdam-rijen gecontroleerd. De resultaten
staan in `technical_summary.json`. `manifest.json` en `checksums.sha256` maken
latere integriteitscontrole mogelijk. De twee PDF-handleidingen zijn op 10 juli
2026 technisch geopend en visueel gecontroleerd.
