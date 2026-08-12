/**
 * Bronnencatalogus van de monitor — de enige plek waar bron-metadata en de
 * oorspronkelijke vindplaats (URL) op internet staan. Gebruikt door het
 * Bronnen-tabblad en door deep-links (state.openSource(id)) elders in de tool.
 *
 * Inhoudelijk gebaseerd op external-data/DATA_CATALOGUS.md; de vier `kern`-
 * bronnen zijn de bronnen die de monitor daadwerkelijk verwerkt.
 */

import type { ViewId } from '../App'

export type SourceStatus = 'kern' | 'beschikbaar' | 'bekeken'

export interface SourceLink {
  label: string
  url: string
}

export interface Source {
  /** anker-id, ook gebruikt in state.openSource(id) */
  id: string
  name: string
  provider: string
  status: SourceStatus
  /** oorspronkelijke vindplaats op internet */
  url: string
  /** aanvullende officiële vindplaatsen (StatLine, OData, …) */
  links?: SourceLink[]
  /** waar in de tool deze bron wordt gebruikt (alleen kernbronnen) */
  usedFor?: string
  /** structured versie van usedFor: welke tabbladen tonen deze bron in hun footnote */
  relatedViews?: ViewId[]
  coverage: string
  content: string
  /** aandachtspunt / interpretatiewaarschuwing */
  note?: string
  license: string
}

export const STATUS_META: Record<SourceStatus, { label: string; blurb: string }> = {
  kern: {
    label: 'In de monitor verwerkt',
    blurb:
      'Deze bronnen vormen de data die de monitor toont en de kaart tekent.',
  },
  beschikbaar: {
    label: 'Gedownload en klaar voor gebruik',
    blurb:
      'Openbare bronnen die zijn geïnventariseerd en gedownload (map external-data/), maar nog niet in de tool zijn opgenomen. Zie de aannames in de Verantwoording waarom.',
  },
  bekeken: {
    label: 'Bekeken, niet opgenomen',
    blurb:
      'Bronnen die zijn beoordeeld maar (nog) niet als databestand zijn opgenomen — meestal door ontbrekend wijkniveau, een beperkte licentie of het ontbreken van een stabiele bulkdownload.',
  },
}

export const SOURCES: Source[] = [
  /* ---------------- kern: daadwerkelijk verwerkt ---------------- */
  {
    id: 'cbs-kwb',
    name: 'CBS — Kerncijfers Wijken en Buurten (KWB) 2016–2025',
    provider: 'Centraal Bureau voor de Statistiek',
    status: 'kern',
    url: 'https://www.cbs.nl/nl-nl/reeksen/publicatie/kerncijfers-wijken-en-buurten',
    links: [
      { label: 'Reekspagina (alle jaargangen)', url: 'https://www.cbs.nl/nl-nl/reeksen/publicatie/kerncijfers-wijken-en-buurten' },
      { label: 'StatLine 2025 — 86165NED', url: 'https://www.cbs.nl/nl-nl/cijfers/detail/86165NED' },
      { label: 'StatLine 2024 — 85984NED', url: 'https://www.cbs.nl/nl-nl/cijfers/detail/85984NED' },
      { label: 'StatLine 2023 — 85618NED', url: 'https://www.cbs.nl/nl-nl/cijfers/detail/85618NED' },
      { label: 'Onderzoeksomschrijving KWB', url: 'https://www.cbs.nl/nl-nl/onze-diensten/methoden/onderzoeksomschrijvingen/korte-onderzoeksomschrijvingen/kerncijfers-wijken-en-buurten' },
    ],
    usedFor:
      'De volledige demografische en sociaaleconomische basis van de monitor: bevolking, leeftijd, huishoudens, herkomst, inkomen, vermogen, uitkeringen, armoede, opleiding, WOZ, woningvoorraad, Wmo en jeugdzorg — op alle niveaus (stadsdeel, gebied, wijk, buurt).',
    relatedViews: ['kaart', 'trends', 'vooruitblik', 'samenhang', 'tabel'],
    coverage: 'Nederland; gemeente, wijk en buurt; verslagjaren 2016–2025.',
    content:
      'Samenvattende jaarpublicatie met kerncijfers over demografische en sociaaleconomische thema’s per gemeente, wijk en buurt. De reekspagina biedt per jaar een Excelbestand; StatLine geeft de losse jaartabellen.',
    note:
      'De levering 2025 is voorlopig: inkomen, uitkeringen, armoede, jeugdzorg, Wmo en opleiding zijn daarin nog leeg (2024 is dan het laatste jaar). Wijk-/buurtaantallen zijn afgerond op vijftallen; kleine zorgcijfers zijn geheim.',
    license: 'CBS open data — CC BY 4.0; bronvermelding CBS.',
  },
  {
    id: 'rivm-gezondheid',
    name: 'RIVM — Gezondheid per wijk en buurt (50150NED)',
    provider: 'RIVM / CBS',
    status: 'kern',
    url: 'https://data.overheid.nl/dataset/70128-gezondheid-per-wijk-en-buurt--2012-2016-2020-2022-2024--indeling-2024-',
    links: [
      { label: 'Dataset op data.overheid.nl', url: 'https://data.overheid.nl/dataset/70128-gezondheid-per-wijk-en-buurt--2012-2016-2020-2022-2024--indeling-2024-' },
      { label: 'OData-service 50150NED', url: 'https://dataderden.cbs.nl/ODataApi/OData/50150NED' },
    ],
    usedFor:
      'De uitkomstindicatoren (met prefix o_) in het tabblad Samenhang: ervaren gezondheid, mentaal welzijn, eenzaamheid, mantelzorg, moeite met rondkomen en leefstijl.',
    relatedViews: ['samenhang'],
    coverage: 'Nederland; gemeente, wijk en buurt (indeling 2024); meetjaren 2012, 2016, 2020, 2022 en 2024.',
    content:
      'Kleine-gebiedsschattingen van gezondheid, welzijn en leefstijl: o.a. ervaren gezondheid, angst/depressie, stress, eenzaamheid, sociale steun, mantelzorg, moeite met rondkomen, roken, alcohol en bewegen.',
    note:
      'Grotendeels gemodelleerde schattingen op basis van Gezondheidsmonitoren — een buurtwaarde is dus geen rechtstreeks gemeten buurtenquête. In de tool gelabeld als “gemodelleerde schatting”.',
    license: 'CC BY 4.0; bronvermelding RIVM/CBS.',
  },
  {
    id: 'amsterdam-gebieden',
    name: 'Gemeente Amsterdam — Officiële gebiedsindelingen (GGW & stadsdelen)',
    provider: 'Gemeente Amsterdam (Datapunt)',
    status: 'kern',
    url: 'https://api.data.amsterdam.nl/v1/docs/datasets/gebieden.html',
    links: [
      { label: 'Dataset gebieden (API-documentatie)', url: 'https://api.data.amsterdam.nl/v1/docs/datasets/gebieden.html' },
    ],
    usedFor:
      'De leidende gebiedskeuze voor Amsterdam: 9 stadsdelen en de 25 GGW-gebieden (gebiedsgericht werken), waaraan elke CBS-wijk op code is gekoppeld. Opgeslagen in data-prep/gebieden_amsterdam.json.',
    relatedViews: ['kaart', 'trends', 'vooruitblik', 'samenhang', 'tabel'],
    coverage: 'Heel Amsterdam; buurten, wijken, 25 GGW-gebieden en stadsdelen; actuele snapshot (10-7-2026).',
    content:
      'GeoJSON-grenzen en codes voor de officiële Amsterdamse gebiedsindeling. De GGW-laag bevat de 25 gebieden waarop Dynamo gebiedsgericht werkt.',
    note:
      'Administratieve grenzen kunnen wijzigen; koppel statistieken op de expliciete code, niet op naam. De actuele grenslaag past niet automatisch bij historische CBS-cijfers.',
    license: 'Publiek volgens de API-documentatie; controleer de actuele gemeentelijke voorwaarden bij publicatie.',
  },
  {
    id: 'pdok-wijkbuurt',
    name: 'PDOK / CBS — Wijk- en Buurtkaart (kaartgeometrieën)',
    provider: 'PDOK / CBS',
    status: 'kern',
    url: 'https://www.pdok.nl/introductie/-/article/cbs-wijken-en-buurten',
    links: [
      { label: 'Introductie CBS Wijken en Buurten', url: 'https://www.pdok.nl/introductie/-/article/cbs-wijken-en-buurten' },
      { label: 'OGC-webservices (WFS/WMS)', url: 'https://www.pdok.nl/ogc-webservices/-/article/cbs-wijken-en-buurten' },
      { label: 'CBS Cartografie', url: 'https://www.cbs.nl/nl-nl/onze-diensten/open-data/statline-als-open-data/cartografie' },
    ],
    usedFor:
      'De kaartvlakken (choropleth) op de tabbladen Kaart en Vooruitblik: gegeneraliseerde CBS-grenzen van wijken en buurten.',
    relatedViews: ['kaart', 'vooruitblik'],
    coverage: 'Nederland; gemeente, wijk en buurt; jaarlijkse edities.',
    content:
      'Geometrie van alle gemeenten, wijken en buurten met statistische kerncijfers als attribuut, te downloaden via WFS/ATOM/OGC API.',
    note:
      'Gegeneraliseerde grenzen, bedoeld voor vergelijking — niet voor exacte grensbepaling. Gebruik per tijdreeks het indelingsjaar dat bij de indicator hoort.',
    license: 'CBS open data — CC BY 4.0; bronvermelding CBS.',
  },

  /* ---------------- beschikbaar: gedownload, nog niet opgenomen ---------------- */
  {
    id: 'rivm-beweeg',
    name: 'RIVM — Beweegvriendelijke omgeving (50143NED)',
    provider: 'RIVM / CBS',
    status: 'beschikbaar',
    url: 'https://data.overheid.nl/dataset/c4910fc1-263e-40d6-948b-acc80d885848',
    links: [
      { label: 'Dataset op data.overheid.nl', url: 'https://data.overheid.nl/dataset/c4910fc1-263e-40d6-948b-acc80d885848' },
      { label: 'OData-service 50143NED', url: 'https://dataderden.cbs.nl/ODataApi/OData/50143NED' },
    ],
    coverage: 'Nederland; gemeente, wijk en buurt; verslagjaar 2024.',
    content:
      'Totaalscore 0–100 plus vier deelindicatoren: recreatief groen en blauw, sportaccommodaties, sport- en speelplekken en nabijheid van voorzieningen.',
    note: 'Beschrijft mogelijkheden in de fysieke omgeving, niet het feitelijke beweeggedrag. Methodiek in 2020 vernieuwd.',
    license: 'CC BY 4.0; bronvermelding RIVM/CBS.',
  },
  {
    id: 'rivm-regiobeeld',
    name: 'RIVM — Regiobeeld wijk en buurt (50149NED)',
    provider: 'RIVM (o.b.v. Vektis)',
    status: 'beschikbaar',
    url: 'https://dataderden.cbs.nl/ODataApi/OData/50149NED',
    links: [{ label: 'OData-service 50149NED', url: 'https://dataderden.cbs.nl/ODataApi/OData/50149NED' }],
    coverage: 'Gemeente, wijk en buurt (indeling 2024); 2014–2023.',
    content:
      'Zorgkosten en aantallen patiënten per zorgsector (o.a. farmacie, ggz, huisartsenzorg, verpleging/verzorging), plus SES-context.',
    note: '“Aantal”, “per 10.000” en “score” zijn verschillende cijfersoorten — niet mengen. Kosten zeggen iets anders dan onvervulde behoefte.',
    license: 'CC BY 4.0 volgens de publicatievoorwaarden.',
  },
  {
    id: 'cbs-ses-woa',
    name: 'CBS — SES-WOA sociaaleconomische status (86296NED)',
    provider: 'Centraal Bureau voor de Statistiek',
    status: 'beschikbaar',
    url: 'https://www.cbs.nl/nl-nl/cijfers/detail/86296NED',
    links: [
      { label: 'StatLine 86296NED', url: 'https://www.cbs.nl/nl-nl/cijfers/detail/86296NED' },
      { label: 'OData-service', url: 'https://opendata.cbs.nl/ODataApi/OData/86296NED' },
    ],
    coverage: 'Gemeente, wijk en buurt (indeling 2025); 2014–2024.',
    content:
      'SES-WOA-totaalscore en de componenten financiële welvaart, opleidingsniveau en recent arbeidsverleden, met betrouwbaarheidsgrenzen.',
    note: 'Een relatieve score is geen percentage; 2024 kan voorlopig zijn. Gebruik bij kleine gebieden de betrouwbaarheidsinformatie.',
    license: 'CC BY 4.0; bron CBS.',
  },
  {
    id: 'cbs-nabijheid',
    name: 'CBS — Nabijheid voorzieningen (86270NED)',
    provider: 'Centraal Bureau voor de Statistiek',
    status: 'beschikbaar',
    url: 'https://www.cbs.nl/nl-nl/cijfers/detail/86270NED',
    links: [
      { label: 'StatLine 86270NED', url: 'https://www.cbs.nl/nl-nl/cijfers/detail/86270NED' },
      { label: 'OData-service', url: 'https://opendata.cbs.nl/ODataApi/OData/86270NED' },
    ],
    coverage: 'Gemeente, wijk en buurt (indeling 2025); verslagjaar 2025.',
    content:
      'Afstanden tot en aantallen binnen afstandsgrenzen van zorg, onderwijs, kinderopvang, detailhandel, horeca, groen, sport, OV en cultuur.',
    note: 'Afstand is berekend over de weg vanaf bewoonde adressen — geen reistijd of toegankelijkheid. Controleer per variabele de definitie.',
    license: 'CC BY 4.0; bron CBS.',
  },
  {
    id: 'cbs-sociaal-domein',
    name: 'CBS — Gebruik voorzieningen sociaal domein (85994NED)',
    provider: 'Centraal Bureau voor de Statistiek',
    status: 'beschikbaar',
    url: 'https://www.cbs.nl/nl-nl/cijfers/detail/85994NED',
    links: [
      { label: 'StatLine 85994NED', url: 'https://www.cbs.nl/nl-nl/cijfers/detail/85994NED' },
      { label: 'OData-service', url: 'https://opendata.cbs.nl/ODataApi/OData/85994NED' },
    ],
    coverage: 'Gemeente en wijk; definitieve jaarcijfers 2024.',
    content: 'Personen en huishoudens naar aantal en combinatie van voorzieningen uit Wmo, Jeugdwet en Participatiewet.',
    note: 'Veel rijen zijn dimensiecombinaties en dus niet optelbaar. Alleen wijkniveau. Een lege waarde kan door onderdrukking geen nul betekenen.',
    license: 'CC BY 4.0; bron CBS.',
  },
  {
    id: 'cbs-wmo',
    name: 'CBS — Wmo-cliënten naar type (86158NED)',
    provider: 'Centraal Bureau voor de Statistiek',
    status: 'beschikbaar',
    url: 'https://www.cbs.nl/nl-nl/cijfers/detail/86158NED',
    links: [
      { label: 'StatLine 86158NED', url: 'https://www.cbs.nl/nl-nl/cijfers/detail/86158NED' },
      { label: 'OData-service', url: 'https://opendata.cbs.nl/ODataApi/OData/86158NED' },
    ],
    coverage: 'Gemeente en wijk; voorlopige jaarcijfers 2025.',
    content: 'Wmo-cliënten en maatwerkvoorzieningen naar type, absoluut en/of relatief.',
    note: 'Registratiegebruik hangt af van toegang en beleid en meet geen latente vraag. Voorlopige cijfers; alleen wijkniveau.',
    license: 'CC BY 4.0; bron CBS.',
  },
  {
    id: 'cbs-jeugdzorg',
    name: 'CBS — Jeugdzorg in natura (86204NED)',
    provider: 'Centraal Bureau voor de Statistiek',
    status: 'beschikbaar',
    url: 'https://www.cbs.nl/nl-nl/cijfers/detail/86204NED',
    links: [
      { label: 'StatLine 86204NED', url: 'https://www.cbs.nl/nl-nl/cijfers/detail/86204NED' },
      { label: 'OData-service', url: 'https://opendata.cbs.nl/ODataApi/OData/86204NED' },
    ],
    coverage: 'Land, gemeente en wijk; voorlopige jaarcijfers 2025.',
    content: 'Jongeren en trajecten naar jeugdzorgvorm, leeftijd, huishoudsituatie en verwijzer.',
    note: 'Dimensiecombinaties overlappen — niet optellen zonder de populatiedefinitie te controleren. Alleen wijkniveau.',
    license: 'CC BY 4.0; bron CBS.',
  },
  {
    id: 'vektis-gzs',
    name: 'Vektis — Gemeentezorgspiegel Wmo (2025)',
    provider: 'Vektis',
    status: 'beschikbaar',
    url: 'https://www.vektis.nl/gemeentezorgspiegel/data',
    links: [{ label: 'Gemeentezorgspiegel — beschikbare data', url: 'https://www.vektis.nl/gemeentezorgspiegel/data' }],
    coverage: 'Land, regio, gemeente, wijk en buurt (indeling 2024); 2019–2024.',
    content:
      'Unieke Wmo-cliënten per arrangement (hulp bij huishouden, hulpmiddelen, begeleiding, dagbesteding, beschermd wonen, opvang) en leeftijdsgroep, op buurtniveau.',
    note:
      'Fijner en langer dan CBS 86158NED, maar met andere definities. Categorieën <10 cliënten ontbreken; aantallen afgerond op tientallen. Copyright Vektis, geen expliciete open licentie — hergebruik in een publieke tool eerst met Vektis afstemmen.',
    license: 'Publiek downloadbaar; copyright Vektis, geen expliciete open licentie.',
  },
  {
    id: 'amsterdam-bbga',
    name: 'Amsterdam O&S — Basisbestand Gebieden Amsterdam (BBGA)',
    provider: 'Onderzoek & Statistiek Amsterdam',
    status: 'beschikbaar',
    url: 'https://onderzoek.amsterdam.nl/dataset/basisbestand-gebieden-amsterdam-bbga',
    links: [{ label: 'BBGA op onderzoek.amsterdam.nl', url: 'https://onderzoek.amsterdam.nl/dataset/basisbestand-gebieden-amsterdam-bbga' }],
    coverage: 'Amsterdam; stadsdelen, 25 gebieden, wijken en buurten; 2001–2055 (incl. prognoses); 918 variabelen.',
    content:
      'De breedste Amsterdam-specifieke bron: bevolking, huishoudens, inkomen, armoede, werk, participatie, onderwijs, jeugd, zorg/welzijn, veiligheid, wonen en prognoses, met metadata per variabele.',
    note: 'Bevat historie én prognoses; niet elke indicator bestaat voor elk jaar. Gebiedsgrenzen veranderden. Volg de variabelemetadata; leg de gebruiksvoorwaarden vast vóór publicatie.',
    license: 'Openbaar aangeboden; geen eenduidige licentietekst in de download — voorwaarden vastleggen vóór herpublicatie.',
  },
  {
    id: 'leefbaarometer',
    name: 'BZK — Leefbaarometer 3.0 (meting 2024)',
    provider: 'Ministerie van BZK / Leefbaarometer',
    status: 'beschikbaar',
    url: 'https://www.leefbaarometer.nl/page/Opendata',
    links: [{ label: 'Leefbaarometer open data', url: 'https://www.leefbaarometer.nl/page/Opendata' }],
    coverage: 'Gemeente, wijk en buurt; meetjaren 2002–2024.',
    content:
      'Samengestelde leefbaarheidsscore en de dimensies fysieke omgeving, onveiligheid, sociale samenhang, voorzieningen en woningvoorraad.',
    note: 'Een samengesteld model, geen directe meting van gezondheid of zorgvraag. Gebruik als context, niet als causale verklaring.',
    license: 'CC0 volgens de open-datapagina.',
  },
  {
    id: 'amsterdam-voorzieningen',
    name: 'Gemeente Amsterdam — Maatschappelijke voorzieningen',
    provider: 'Gemeente Amsterdam (Datapunt)',
    status: 'beschikbaar',
    url: 'https://api.data.amsterdam.nl/v1/docs/datasets/maatschappelijke_voorzieningen.html',
    links: [{ label: 'Dataset maatschappelijke voorzieningen', url: 'https://api.data.amsterdam.nl/v1/docs/datasets/maatschappelijke_voorzieningen.html' }],
    coverage: 'Amsterdam; puntlocaties, koppelbaar aan buurt/wijk/GGW; actuele snapshot.',
    content: 'Ruimtelijke aanbodlaag voor zorg, welzijn, ontmoeting en sport: naam, domein, categorie, adres, postcode en stadsdeel per locatie.',
    note: 'Een gemeentelijke inventaris, geen volledige sociale kaart. Een punt zegt niets over capaciteit, wachttijd of gebruik.',
    license: 'Publiek volgens de API-documentatie; actuele voorwaarden controleren.',
  },
  {
    id: 'amsterdam-sport',
    name: 'Gemeente Amsterdam — Sportvoorzieningen',
    provider: 'Gemeente Amsterdam (Datapunt)',
    status: 'beschikbaar',
    url: 'https://api.data.amsterdam.nl/v1/docs/datasets/sport.html',
    links: [{ label: 'Dataset sport', url: 'https://api.data.amsterdam.nl/v1/docs/datasets/sport.html' }],
    coverage: 'Amsterdam; punt-, lijn- en vlaklagen; actuele snapshot.',
    content: 'Acht lagen: aanbieders, gymzalen, hallen, hardlooproutes, openbare sportplekken, parken, velden en zwembaden.',
    note: 'Tel objecttypen niet door elkaar op als één aanbodmaat. Bevat geen deelname, tarieven of openingsuren.',
    license: 'Publiek volgens de API-documentatie; actuele voorwaarden controleren.',
  },
  {
    id: 'amsterdam-scholen',
    name: 'Gemeente Amsterdam — Schoolgebouwen en kengetallen',
    provider: 'Gemeente Amsterdam (Datapunt)',
    status: 'beschikbaar',
    url: 'https://api.data.amsterdam.nl/v1/docs/datasets/schoolgebouwen.html',
    links: [{ label: 'Dataset schoolgebouwen', url: 'https://api.data.amsterdam.nl/v1/docs/datasets/schoolgebouwen.html' }],
    coverage: 'Amsterdam; adres, wijk, stadsdeel; actuele snapshot.',
    content: 'Schooltype, gebouwkenmerken, gebruik, leerlingaantallen, prognoses, ruimtebehoefte en achterstandsscore.',
    note: 'Genormaliseerde tabellen — maak eerst een gedocumenteerde join en voorkom dubbeltelling. Leerlingprognose is geen directe zorgvraag.',
    license: 'Publiek volgens de API-documentatie; actuele voorwaarden controleren.',
  },
  {
    id: 'amsterdam-woningbouw',
    name: 'Gemeente Amsterdam — Openbare woningbouwplannen',
    provider: 'Gemeente Amsterdam (Datapunt)',
    status: 'beschikbaar',
    url: 'https://api.data.amsterdam.nl/v1/docs/datasets/nieuwbouwplannen.html',
    links: [{ label: 'Dataset nieuwbouwplannen', url: 'https://api.data.amsterdam.nl/v1/docs/datasets/nieuwbouwplannen.html' }],
    coverage: 'Amsterdam; buurt, wijk, GGW-gebied en stadsdeel; actuele snapshot.',
    content: 'Planlocaties met planfase en woningsegmenten (o.a. sociale huur, middensegment, jongeren- en studentenwoningen).',
    note: 'Plannen kunnen wijzigen of vervallen — gebruik planfase als scenario, niet als gerealiseerde bevolking.',
    license: 'Creative Commons Naamsvermelding volgens de API-documentatie.',
  },
  {
    id: 'amsterdam-focus',
    name: 'Amsterdam O&S — Outcomemonitor focusgebieden',
    provider: 'Onderzoek & Statistiek Amsterdam',
    status: 'beschikbaar',
    url: 'https://onderzoek.amsterdam.nl/dataset/focusgebieden-amsterdam',
    links: [{ label: 'Focusgebieden op onderzoek.amsterdam.nl', url: 'https://onderzoek.amsterdam.nl/dataset/focusgebieden-amsterdam' }],
    coverage: 'Amsterdam; focusgebieden Zuidoost, Noord en Nieuw-West; juni 2026.',
    content: 'Indicatoren over inclusie/participatie, jeugd, bestaanszekerheid en sociale ontwikkeling voor drie gebiedsprogramma’s.',
    note: 'Alleen leer- en benchmarkbron; niet als Oost-benchmark — Oost valt niet onder deze programma’s.',
    license: 'Openbare O&S-download; hergebruik vastleggen vóór publicatie.',
  },
  {
    id: 'amsterdam-veiligheid',
    name: 'Amsterdam O&S — Veiligheidsindex (2026-1)',
    provider: 'Onderzoek & Statistiek Amsterdam',
    status: 'beschikbaar',
    url: 'https://onderzoek.amsterdam.nl/dataset/openbare-orde-en-veiligheid',
    links: [{ label: 'Openbare orde en veiligheid', url: 'https://onderzoek.amsterdam.nl/dataset/openbare-orde-en-veiligheid' }],
    coverage: 'Amsterdam; veiligheidsmonitorgebieden; meerdere jaren.',
    content: 'Geregistreerde criminaliteit en samengestelde veiligheidsindicatoren, met vergelijkingsmogelijkheden.',
    note: 'Leefomgevingscontext, geen directe maat voor gezondheid of zorgvraag. Label registraties/indices zichtbaar.',
    license: 'Openbare O&S-download; hergebruik vastleggen vóór publicatie.',
  },

  /* ---------------- bekeken: niet opgenomen ---------------- */
  {
    id: 'ggd-gezondheid-in-beeld',
    name: 'GGD — Gezondheid in Beeld',
    provider: 'GGD GHOR Nederland / GGD Amsterdam',
    status: 'bekeken',
    url: 'https://ggdgezondheidinbeeld.nl/mosaic/',
    links: [
      { label: 'Gezondheid in Beeld', url: 'https://ggdgezondheidinbeeld.nl/mosaic/' },
      { label: 'Datasetregistratie', url: 'https://data.overheid.nl/dataset/mairbhcp_xlteg' },
    ],
    coverage: 'Lokale GGD-thema’s: fysieke/mentale gezondheid, zorggebruik, eenzaamheid, leefstijl, jeugd.',
    content: 'Zeer relevant dashboard, per grafiek te exporteren, maar zonder stabiele bulk-API — nog niet reproduceerbaar op te nemen.',
    note: 'Bouw later een expliciete connector zodra GGD Amsterdam een bulkexport of API-contract levert.',
    license: 'Zie de dashboardvoorwaarden van GGD.',
  },
  {
    id: 'nivel',
    name: 'Nivel — Zorgregistraties Eerste Lijn',
    provider: 'Nivel',
    status: 'bekeken',
    url: 'https://www.nivel.nl/nl/panels-en-registraties/nivel-zorgregistraties-eerste-lijn',
    links: [{ label: 'Nivel Zorgregistraties Eerste Lijn', url: 'https://www.nivel.nl/nl/panels-en-registraties/nivel-zorgregistraties-eerste-lijn' }],
    coverage: 'Huisartsen- en eerstelijnszorg; geen open klein-gebiedsbulkbestand.',
    content: 'Inhoudelijk rijke registraties, maar gedetailleerde wijk/buurtdata vereisen een aanvraag en voorwaarden.',
    license: 'Aanvraag en voorwaarden vereist.',
  },
  {
    id: 'vektis-open',
    name: 'Vektis — Open data',
    provider: 'Vektis',
    status: 'bekeken',
    url: 'https://www.vektis.nl/open-data',
    links: [{ label: 'Vektis open data', url: 'https://www.vektis.nl/open-data' }],
    coverage: 'Vooral gemeente of postcode-3 — onder het gekozen minimum van wijkniveau.',
    content: 'De Wmo-publicatie van de Gemeentezorgspiegel is wél opgenomen; de overige open bestanden voldoen niet aan het wijkniveau-minimum. RIVM 50149NED levert al Vektis-afgeleide zorgcijfers op wijk/buurt.',
    license: 'Beperkter dan een open licentie.',
  },
  {
    id: 'atlas-leefomgeving',
    name: 'Atlas Leefomgeving / Nationaal Georegister',
    provider: 'RIVM e.a.',
    status: 'bekeken',
    url: 'https://www.atlasleefomgeving.nl/',
    links: [{ label: 'Atlas Leefomgeving', url: 'https://www.atlasleefomgeving.nl/' }],
    coverage: 'Luchtkwaliteit, geluid, hitte, groen en milieugezondheid — vaak als raster/WFS.',
    content: 'Relevant, maar aangeboden als raster of kaartlaag en niet vooraf geaggregeerd tot CBS-wijk/buurt. Opname vraagt een aparte GIS-pijplijn — zinvolle tweede fase.',
    license: 'Wisselend per laag.',
  },
]

/** Bron opzoeken op id (voor deep-links). */
export function findSource(id: string): Source | undefined {
  return SOURCES.find((s) => s.id === id)
}

export const STATUS_ORDER: SourceStatus[] = ['kern', 'beschikbaar', 'bekeken']
