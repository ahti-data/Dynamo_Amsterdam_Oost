# CBS Microdata — onderzoeksopzet binnen ahti-project 9097

Dit onderzoek loopt **volledig binnen ahti** (Amsterdam Health & Technology
Institute), onder het lopende, gemachtigde project **9097 — "Zorgsystemen:
gebruik over de regelingen heen"** (looptijd 2021-11-01 t/m 2026-12-31).
**GelijkGezond en Dynamo staan hier los van**: de bestaande Dynamo Oost
Monitor (buurtgemiddelden uit CBS Kerncijfers Wijken en Buurten) dient
uitsluitend als *inspiratie* voor het type inzichten dat op persoonsniveau
interessant is — niet als samenwerkingspartner of gebruiker van de microdata.
Er is dus geen toegangs-, partner- of publicatievraagstuk (zie eerdere versie
van dit document); dit is een **analyseplan** voor een lopend project.

## 1. Team (ahti-intern)

| Rol | Verantwoordelijkheid |
|-----|----------------------|
| **CBS microdata-expert (lead)** | Bestandsselectie binnen project 9097, koppelsleutels, disclosure-regels |
| **Epidemioloog/sociaal-demograaf** | Onderzoeksvragen en doelgroepafbakening (geïnspireerd op de doelgroepindeling van de Dynamo-monitor: ouderen, kinderen, jongeren, alleenwonenden, aankomende senioren, huishoudens) |
| **R-analist/data-scientist** | Inleesroutines, koppelscript en analysepijplijn in R binnen de beveiligde omgeving (BMO) |
| **Privacyjurist/AVG-adviseur** | AVG-grondslag en disclosure control op output |

## 2. Doel en onderzoeksvragen

**Doel:** de winst van koppeling op persoons-/huishoudenniveau benutten om te
laten zien hoe zorg- en ondersteuningsgebruik **over de regelingen heen**
(Zvw, Wlz, Wmo, Jeugdwet, Participatiewet) samenhangt en stapelt bij
individuen en huishoudens — iets wat met buurtgemiddelden (de huidige
KWB-aanpak) alleen als correlatie tussen twee gebiedscijfers zichtbaar is,
nooit als samenloop bij dezelfde persoon.

**Onderzoeksvragen:**
1. Welke combinaties van persoons-/huishoudkenmerken (leeftijd, inkomen,
   huishoudsamenstelling, SES) voorspellen gebruik van meerdere regelingen
   tegelijk (bijv. Wmo + GGZ + bijstand) bij dezelfde persoon?
2. Hoe verhouden individuele samenhangen zich tot de bestaande
   buurtgemiddelde-correlaties (ecologische vs. individuele samenhang)?
3. Hoe verlopen trajecten door de tijd (van bijstand naar Wmo, van jeugdhulp
   naar GGZ in de jongvolwassenheid, etc.) — als basis voor een
   cohort-gebaseerde in plaats van gebiedstrend-gebaseerde voorspelling?
4. Wat is de rol van sterfte (DOODOORZTAB/GBAOVERLIJDENTAB) als
   eindpunt van stapeling van regelingengebruik (bijv. zorgmijding,
   oversterfte bij multi-probleemhuishoudens)?

## 3. Beschikbare bestanden

### 3.0 Stapelingsmonitor 2012-2024 (STAPMON) — primaire ruggengraat

Naast de 66 losse regelingenbestanden onder project 9097 (§3.1) heeft ahti
ook toegang tot de **Stapelingsmonitor 2012-2024**, een door het CBS in
opdracht van het ministerie van SZW (medegefinancierd door J&V, BZK, OCW en
VWS) samengesteld **maatwerk microdatabestand**
(cbs.nl/.../maatwerk-microdatabestanden/personen/stapelingsmonitor-2012-2024).
Volgens het CBS-documentatierapport (opgehaald 2 december 2025) is dit
letterlijk *"een microdatabestand ten behoeve van onderzoek naar stapeling
van regelingen en voorzieningen en (signalen van) problematiek in het
sociaal domein"* — precies de vraag uit §2, al kant-en-klaar op
persoon-jaarniveau beantwoord, in plaats van zelf opgebouwd uit losse
regelingenbestanden.

**Populatie en eenheid:** alle personen die op 31 december van het
verslagjaar met een geldig adres in Nederland stonden ingeschreven in de BRP.
Uniek op **RINPERSOON(S)**, met daarnaast **twee verschillende
huishoudsleutels** (zie §4). Het bestand is *geen* officieel vastgesteld
publicatiebestand — geaggregeerde uitkomsten kunnen afwijken van StatLine.

**Levering per thema, niet per variabele.** CBS levert een thema altijd in
zijn geheel; losse variabelen uit een thema aanvragen is niet mogelijk. Voor
een deel van de variabelen (Vektis/GGZ-zorgkosten, CAK/Wmo, WSW, Wlz, Jeugd,
Halt, justitiële variabelen, Wsnp, Medicijn, Wanbetaler zorgverzekering,
Doelgroepregister, Kinderopvangtoeslag, de smalle schulddefinitie, Aftrek
bijzondere ziektekosten en Herkomstland) is bovendien **aparte toestemming
van de bronleverancier en/of CBS-vakafdeling** nodig — dit is een concreet
actiepunt naast de STAPMON-projectkoppeling zelf (zie §9).

De 15 thema's, met de voor dit onderzoek relevantste inhoud:

| Thema | Kerninhoud (selectie) |
|-------|------------------------|
| **Achtergrondkenmerken** | Geslacht, leeftijd, herkomst/generatie (nieuwe indeling vanaf 2020), burgerlijke staat, huishoudsamenstelling (aantal kinderen/volwassenen/65-plussers), **LANDSDEEL/PROVINCIE/GEM/WC/BC — gemeente-, wijk- en buurtcode op basis van woonadres zit al in dit thema**, type huishouden, afstand tot dichtstbijwonend kind |
| **Onderwijs** | Hoogst behaalde/gevolgde onderwijsniveau (HBOPL/HGOPL, SOI-indeling), startkwalificatie, voortijdig schoolverlaten (VSV), schoolverzuim/Halt-verwijzing, schooladvies VO |
| **Inkomen** | Persoonlijk/huishoudinkomen (besteedbaar, primair, bruto, gestandaardiseerd), **ARMOEDE en LANGARMOEDE** (nieuwe CBS/SCP/Nibud-armoededefinitie, beschikbaar vanaf verslagjaar **2018**, sinds 2025 toegevoegd), plus de oude LAAGINK/LANGLAAGINK |
| **Vermogen en schulden** | Huishoudvermogen (excl./incl. eigen woning), hypotheekschuld, Wsnp-traject, wanbetaler zorgverzekering, **SMALLE_SCHULD / SMALLE_SCHULD_HUISHOUDEN** — geregistreerde problematische schulden volgens een 12-criteria "smalle definitie" (BKR, zorgpremie, CJIB/Mulder, Belastingdienst, DUO, bijstandsvordering, UWV, SVB, CAK Wlz/Wmo eigen bijdrage), beschikbaar vanaf 2019 |
| **Toeslagen e.d.** | Huurtoeslag, zorgtoeslag, kindgebonden budget, kinderopvangtoeslag (bedrag + aantal), aftrek bijzondere ziektekosten |
| **Werk** | Werknemer/zelfstandige (zzp/zmp), bedrijfstak, contractsoort, arbeidsduur, deeltijdfactor, re-integratievoorzieningen gemeente (SRG: loonkostensubsidie, beschut werk, jobcoaching, etc.) — vanaf 2017 |
| **Doelgroepregister & WSW** | Doelgroepregister, Wsw-indicatie/dienstbetrekking/regulier — aflopend sinds de WSW-instroomstop in 2015 |
| **Uitkeringen** | WW, arbeidsongeschiktheid (WAO/WIA→IVA+WGA/WAZ/Wajong), bijstand (Participatiewet/IOAW/IOAZ + bijzondere bijstand), IOW, Ziektewet, Tozo (2020-2021), plus afgeleide **HOPPER/BIJSTANDSDUUR** en in-/uitstroom-indicatoren |
| **Wmo** | Wmo-hulp naar vorm, o.b.v. de vrijwillige gemeentelijke monitor sociaal domein (GMSD) én CAK-registratie (dit laatste tot en met 2019) — **let op: niet alle gemeenten leveren elk jaar volledig aan de GMSD**, checken of Amsterdam consistent aanlevert |
| **Jeugd** | Jeugdhulp/-bescherming/-reclassering naar vorm (ambulant, pleegzorg, gesloten, netwerk, etc.), **JURIDISCHE_OUDER_KIND_JEUGDZORG** (koppelt jeugdzorg aan de ouder ook als het kind niet in hetzelfde huishouden woont), jeugd-PGB |
| **Wlz** | Wlz-indicatie, verblijf, volledig/modulair pakket thuis (VPT/MPT), PGB |
| **Gezondheid & Welzijn** | **GGZ** (vanaf 2022 één variabele, vóór 2022 basis_ggz/special_ggz — trendbreuk door overgang DBC → zorgprestatiemodel), wijkverpleging, LVB (lichte verstandelijke beperking, samengestelde indicator), totale zorgkosten (in-/exclusief GGZ), eigen risico; enkele variabelen (ervaren gezondheid, roken, alcohol, drugs, overgewicht, beweegnorm) komen uit de **gezondheidsenquête** en zijn dus steekproefgebaseerd — vereisen weging |
| **Gezondheid & Medicijngebruik** | Medicijnuitgifte naar ATC-groep: **psychofarmaca, antidepressiva, antipsychotica, verslavingsmiddelen**, plus hoofdtype (A–Y) |
| **Rechtsbescherming en veiligheid** | Verdachte van een misdrijf (naar type), gedetineerd (+ zwaarste delict, detentierecidive binnen 36 mnd), afdoening OM/rechter, slachtofferschap, Halt, gesubsidieerde rechtsbijstand — een **domein dat nog niet in het eerdere analyseplan zat** en de "stapeling" nu ook naar veiligheid/justitie uitbreidt |
| **Wonen** | Woonsituatie: koop, huur met/zonder huurtoeslag, institutioneel huishouden |

**Belangrijk — huidige koppeling:** ahti heeft momenteel alleen
**Achtergrondkenmerken** en **Inkomen** gekoppeld, en wel onder een ander
lopend project (**10053, "Pandemische Paraatheid voor Infectieziekten"**),
niet onder 9097. Voor dit onderzoek moet dus worden nagegaan of (a) deze twee
thema's hergebruikt/overgeheveld kunnen worden naar 9097, en (b) de overige
relevante thema's (in elk geval Uitkeringen, Wmo, Wlz, Jeugd, Gezondheid &
Welzijn, Gezondheid & Medicijngebruik, en voor de veiligheidsdimensie
Rechtsbescherming en veiligheid) apart worden aangevraagd bij CBS
Microdata Services, inclusief de eventueel benodigde
bronleverancierstoestemming — zie §9, stap 0.

Zodra de relevante STAPMON-thema's onder 9097 beschikbaar zijn, vormen zij de
**primaire bron** voor de cross-domein indicatoren en de stapelingsindex uit
§5; de losse regelingenbestanden in §3.1 dienen dan vooral als **verdieping**
(klinische diagnosedetail, exacte DBC-/zorgprofielniveau) waar de thematische
STAPMON-modules niet in voorzien.

### 3.1 Losse regelingenbestanden binnen project 9097

66 bestanden zijn gekoppeld aan project 9097. Geordend naar domein:

### Basis: persoon, huishouden, geografie

| Bestand | Inhoud |
|---------|--------|
| GBAPERSOONTAB | Persoonskenmerken (geslacht, geboortejaar, migratieachtergrond) |
| GBAPERSOONKTAB | Persoonskenmerken, jaarversie (voor paneelopbouw) |
| GBAHUISHOUDENSBUS | Huishoudsamenstelling |
| KOPPELPERSOONHUISHOUDEN | Koppeltabel persoon ↔ huishouden |
| PARTNERBUS | Partnerrelaties |
| KINDOUDERTAB | Ouder-kindrelaties (relevant voor jeugdhulp/gezinscontext) |
| GBAADRESOBJECTBUS | Verblijfsobject-/adreskenmerken |
| VSLGWBTAB | Gemeente-/wijk-/buurtcode (GWB) — koppelt personen aan Oost-wijken |
| NIETVSLGWBTAB | Personen/objecten zonder GWB-koppeling (bijv. instellingsadressen) — **check met CBS/ahti-datamanager hoe dit de Oost-selectie beïnvloedt** |
| GBAOVERLIJDENTAB | Overlijdensdatum |
| DOODOORZTAB | Doodsoorzaak |
| STUDERENDENBUS | Onderwijsdeelname |
| SESWOA | Individuele sociaaleconomische status-score (Wonen/Opleiding/Arbeid) |
| INHATAB | Huishoudinkomen |

### Participatiewet / bijstand

| Bestand | Inhoud |
|---------|--------|
| BIJSTANDUITKERINGTAB | Bijstandsuitkeringen |
| UITSTROOMOMTAB | Uitstroomreden bijstand |
| UITSTROOMRECHTERTAB | Uitstroom rechthebbende |

### Jeugdwet

| Bestand | Inhoud |
|---------|--------|
| JGDHULPBUS | Jeugdhulptrajecten |
| JGDBESCHERMBUS | Jeugdbeschermingsmaatregelen |

### Wmo / Wlz (langdurige zorg en ondersteuning)

| Bestand | Inhoud |
|---------|--------|
| WMOBUS | Wmo-arrangementen |
| GEBWMOTAB | Gebruik Wmo-maatwerkvoorzieningen |
| INDICWLZTAB | Wlz-indicaties |
| INDICAWBZTAB | AWBZ-indicaties (historisch, vóór Wlz/Wmo 2015) |
| GEBWLZTAB | Gebruik Wlz |
| WLZZINTAB | Wlz zorg in natura |
| PGBWLZWMOJWTAB | Persoonsgebonden budget over Wlz/Wmo/Jeugdwet — expliciet cross-domein |

### Zvw — huisarts, ziekenhuis (MSZ), medicijnen

| Bestand | Inhoud |
|---------|--------|
| HUISARTSDECLTAB | Huisartsdeclaraties |
| MEDICIJNTAB | Medicijngebruik |
| ZVWWVPTAB (+2019) | Zvw-verzekerdenpopulatie |
| ZVWZORGKOSTENTAB (+ jaarversies) | Zvw-zorgkosten |
| MSZPRESTATIESVEKTTAB (+ jaarversies) | MSZ-prestaties (Vektis) |
| MSZZORGACTIVITEITENVEKTTAB (+ jaarversies) | MSZ-zorgactiviteiten |
| MSZSUBTRAJECTENTAB, MSZGELEVERDZORGPROFIELTAB, MSZOVERIGEZORGPRODUCTENTAB, MSZDGAddonGeneesmVEKTTAB | MSZ-detailbestanden (subtrajecten, zorgprofielen, dure geneesmiddelen) |
| LBZBASISTAB2013–2023 | Landelijke Basisregistratie Ziekenhuiszorg, basisgegevens per jaar |
| LBZDIAGNOSENTAB2021, LBZDIAGNOSENTAB2023 | Ziekenhuisdiagnoses |
| PRNL | Perinatale Registratie Nederland (zwangerschap/geboorte) |

### GGZ (geestelijke gezondheidszorg)

| Bestand | Inhoud |
|---------|--------|
| GGZDBCTRAJECTENTAB, GGZDBCTRAJECTENHOOFDDIAGTAB | GGZ DBC-trajecten (± hoofddiagnose) |
| GGZDBCGELEVERDZORGPROFIELTAB, GGZDBCZRGPROFIELHOOFDDIAGTAB | GGZ geleverde zorgprofielen |
| GGZZPMPRESTATIETAB | GGZ zorgprestatiemodel |
| GGZDECLVEKTIS | GGZ-declaraties (Vektis) |

**Onduidelijk:** het bestand met naam **"DO"** kon niet eenduidig worden
geïdentificeerd (mogelijk een groepslabel of foutieve rij in de bronlijst,
naast het wél bestaande DOODOORZTAB) — navragen bij de ahti-datamanager
vóór gebruik.

### 3.2 Vastgoed- en verhuisbestanden voor de gentrificatie-analyse (ahti-project 9096)

Voor de gentrificatie-analyse (§6) zijn de vastgoed- en verhuisbestanden
nodig — deze staan **niet onder 9097**, maar onder ahti's andere lopende
project **9096 "Aandoeningen: gebruik over de regelingen heen"**:

| Bestand | Inhoud | Gebruik in §6 |
|---------|--------|----------------|
| BAGWOZTAB | WOZ-waarde per verblijfsobject | Vastgoedkant van gentrificatie, koppelbaar aan wie er woont |
| EIGENDOMTAB | Eigendomsvorm (huur/koop, corporatie vs. particuliere verhuurder) | Signaal voor verkoop sociale huur — een klassieke gentrificatie-driver |
| EIGENDOMWOZBAGTAB | Gecombineerd WOZ + BAG + eigendom | Eén tabel voor de vastgoedkenmerken per object |
| ENERGIELABELCERTIFICATENTAB | Energielabel | Renovatiesignaal |
| **GBAADRESGEBEURTENISBUS** | Verhuisgebeurtenissen per persoon (datum, van/naar-adres) | **Kern van de blijf/vertrek/instroom-decompositie** in §6 |
| LEVCYCLWOONNIETWOONBUS | Woninglevenscyclus (nieuwbouw, sloop, transformatie) | Nieuwbouw/transformatie als gentrificatie-trigger |

Dit betekent dat het onderzoek — net als bij de STAPMON-thema's (§3.0) — een
**tweede project-koppeling** vergt: nagaan of deze bestanden (of het hele
project 9096) samengevoegd kunnen worden met 9097, of dat de
gentrificatie-analyse als afzonderlijk deelproject met eigen doelbinding
loopt. Zie §9, stap 0.

## 4. Koppeling: sleutels en schema

- **RINPERSOON + RINPERSOONS** is de gepseudonimiseerde persoonssleutel
  waarop vrijwel alle bovenstaande bestanden koppelen (GBA-, Zvw-, Wlz-,
  Wmo-, Jeugdwet- en Participatiewet-bestanden, én elk STAPMON-themabestand,
  delen deze sleutel). Alleen records met RINPERSOONS-waarde **'R'** (geldig
  BSN teruggevonden in de BRP) zijn geschikt om te koppelen; 'F'-records
  (ongeldig BSN) niet.
- **Twee verschillende huishoudsleutels** — belangrijk om niet door elkaar te
  halen: (1) **HUISHOUDNR + DATUMAANVANGHH** (in het thema
  Achtergrondkenmerken) aggregeert naar het BRP-huishouden; (2)
  **RINPERSOONSKERN + RINPERSOONKERN** aggregeert naar het huishouden zoals
  gebruikt in de inkomensstatistiek. Beide huishoudindelingen verschillen
  vooral bij institutionele/overige huishoudens. CBS-advies: gebruik de
  inkomensstatistiek-sleutel bij inkomens-/vermogensvariabelen, de
  BRP-sleutel voor de overige variabelen. Buiten STAPMON om legt
  **KOPPELPERSOONHUISHOUDEN** (§3.1) de relatie persoon → huishouden.
- **PARTNERBUS/KINDOUDERTAB** (§3.1) leggen relaties tussen personen binnen
  een huishouden (partner, ouder-kind); STAPMON's eigen
  **JURIDISCHE_OUDER_KIND_JEUGDZORG** (thema Jeugd) doet dit al specifiek
  voor jeugdzorg, ook als het kind niet in hetzelfde huishouden woont als de
  ouder.
- **Geografie zit al in het thema Achtergrondkenmerken**: LANDSDEEL,
  PROVINCIE, GEM (gemeentecode), WC (wijkcode) en BC (buurtcode) op basis van
  woonadres, samen de 8-cijferige GWB-buurtcode — dit is de sleutel om te
  filteren op Amsterdam Oost (dezelfde 15 CBS-wijken WK0363M* als in de
  bestaande monitor). VSLGWBTAB/GBAADRESOBJECTBUS (§3.1) blijven nodig voor
  fijnmaziger periode-detail of voor jaren/bestanden buiten STAPMON.
- **Paneelstructuur:** veel losse regelingenbestanden zijn jaarbestanden
  (LBZBASISTAB*, MSZPRESTATIESVEKTTAB*, ZVWZORGKOSTENTAB*, GBAPERSOONKTAB).
  Voor een longitudinaal individueel panel moeten deze eerst per jaar worden
  ingelezen en dan op RINPERSOON(S) + jaar samengevoegd tot één
  persoon-jaar-bestand (long format) vóór verdere koppeling. De
  **Stapelingsmonitor (§3.0) levert dit paneel al kant-en-klaar** per module
  op persoon-jaarniveau 2012-2024 — voor de thema's die STAPMON dekt is deze
  eigen harmonisatiestap dus niet nodig; alleen de aanvullende, niet-STAPMON
  bestanden (bijv. GGZ DBC-detail, LBZ-diagnoses) vragen nog om zelf bouwen.
- **Referentiepopulatie:** GBAPERSOONTAB + VSLGWBTAB (gefilterd op de Oost-
  wijkcodes) vormt de basispopulatie; alle regelingenbestanden worden hierop
  gejoined (left join vanuit de populatie, niet vanuit de regelingenbestanden
  — anders vallen niet-gebruikers uit de teller).

## 5. Analyseplan

1. **Cross-domein gebruiksindicatoren per persoon-jaar.** Primair uit de
   relevante STAPMON-thema's afleiden: **Uitkeringen** (WW/AO/bijstand),
   **Wmo**, **Wlz**, **Jeugd**, **Gezondheid & Welzijn** (GGZ, LVB,
   zorgkosten) en **Gezondheid & Medicijngebruik** (ATC-groepen); voor de
   financiële kant direct **ARMOEDE/LANGARMOEDE** (thema Inkomen, vanaf 2018)
   en **SMALLE_SCHULD(_HUISHOUDEN)** (thema Vermogen en schulden, vanaf 2019)
   gebruiken — dit zijn al kant-en-klare, multi-bron gevalideerde indicatoren
   voor armoede en problematische schulden, precies de kern van de
   "stapeling"-vraag. Alleen waar STAPMON geen detail biedt (bijv.
   GGZ-hoofddiagnose, MSZ-zorgprofiel) aanvullen uit de losse
   regelingenbestanden (§3.1). Dit vervangt de huidige buurtgemiddelden per
   indicator.
2. **Stapelingsindex.** STAPMON is letterlijk voor dit doel samengesteld: een
   telling van gelijktijdig gebruikte regelingen per persoon-jaar volgt
   direct uit de gekoppelde thema's, eventueel gewogen met
   SOMZORGKOSTEN_INCLGGZ (thema Gezondheid & Welzijn) — het individuele
   equivalent van de "multi-probleemhuishoudens"-vraag die nu alleen
   ecologisch benaderd wordt. Overweeg het thema **Rechtsbescherming en
   veiligheid** (verdachte/gedetineerd/afdoening) als extra dimensie op te
   nemen — dit domein zat nog niet in de oorspronkelijke scope van §2, maar
   sluit natuurlijk aan bij "stapeling van problematiek".
3. **Typologieën op persoons-/huishoudniveau.** Clusteranalyse (k-means of
   latent class analysis) op basis van demografie (leeftijd, migratie-
   achtergrond, SESWOA, huishoudsamenstelling) én gebruikspatroon — het
   individuele analogon van de bestaande buurt-k-means-typologieën
   (`multivar_foundation.json` in de Dynamo-monitor), maar dan zonder
   ecologische aggregatie.
4. **Multilevel modellen** (persoon genest in buurt/wijk): voorspel
   cross-domein gebruik uit persoonskenmerken mét een buurt-random-effect,
   om te toetsen hoeveel van de buurtvariatie in de huidige monitor
   werkelijk individueel verklaarbaar is versus contextueel (buurteffect).
5. **Trajectanalyse/transitiematrices.** Met de jaarpanelen: overgangen
   tussen toestanden volgen (bijv. bijstand → Wmo, jeugdhulp → GGZ bij
   volwassenwording, gebruik → overlijden). Dit vervangt de huidige
   gebiedstrendextrapolatie (`forecast.ts`) door een cohort-gebaseerde
   aanpak, mits de celgroottes per overgang de disclosure-drempel halen.
6. **Sterfte als eindpunt.** DOODOORZTAB/GBAOVERLIJDENTAB koppelen aan
   regelingengebruik in voorgaande jaren, om te onderzoeken of stapeling van
   regelingengebruik samenhangt met (voortijdige) sterfte — een vraag die op
   buurtniveau niet te beantwoorden is.

## 6. Gentrificatie-analyse: uitsplitsing naar Dynamo-doelgroepen

**Aanleiding:** de hypothese (besproken buiten dit document) dat gentrificatie
via instroom van draagkrachtige gezinnen met (jonge) kinderen de behoefte aan
jeugdondersteuning als eerste doet dalen, terwijl ouderen — die minder
verhuizen — er geen last van zouden hebben. Literatuuronderzoek bevestigt het
eerste deel (Boterman's "family gentrifiers"/"yupps" in Amsterdam; NYC
Medicaid-onderzoek: dalende kinderarmoede in gentrificerende buurten komt
vooral door **instroom van welvarende gezinnen**, niet doordat bestaande arme
gezinnen sneller vertrekken) maar weerlegt het tweede deel: ouderen verhuizen
weliswaar minder (een algemeen leeftijdsgebonden gegeven), maar ondervinden
wél degelijk impact zonder te verhuizen (financiële druk, verlies van lokale
voorzieningen, "indirect displacement"). In de Nederlandse context komt
daarbij dat zittende huurders — van alle leeftijden — door schaarste aan
betaalbare alternatieven juist **vastzitten** ("exclusionary displacement"),
niet primair worden weggedrukt. Dit maakt een **empirische toets per
Dynamo-doelgroep** op Oost-microdata waardevoller dan het aannemen van
generieke (vaak Amerikaanse) literatuur.

**Doel:** voor elke Dynamo-doelgroep uit de bestaande monitor (zie
[VOORUITBLIK-TEAM.md](VOORUITBLIK-TEAM.md) §2: ouderen 65+, kinderen 0-14,
jongeren 15-24, alleenwonenden, aankomende senioren 45-64, huishoudens, totaal
inwoners) apart in kaart brengen wat gentrificatiedruk doet met (a) blijf-/
vertrekgedrag en (b) de relevante ondersteuningsbehoefte — in plaats van één
buurtbrede uitkomst.

**Gentrificatie-intensiteit per buurt-jaar** (voorspeller, uit §3.2):
- WOZ-waardestijging (BAGWOZTAB) t.o.v. het Oost-gemiddelde;
- verandering in eigendomsvorm (EIGENDOMTAB): afname sociale huur, toename
  particuliere verhuur/koop;
- nieuwbouw/transformatie (LEVCYCLWOONNIETWOONBUS) als aanjager.

**Per doelgroep, met de relevante uitkomstmaat:**

| Doelgroep | Blijf/vertrek-analyse | Relevante steunbehoefte-indicator |
|-----------|------------------------|-------------------------------------|
| Kinderen (0-14) | Verhuisgeneigdheid van het gezin (via ouder, `KINDOUDERTAB`/`GBAADRESGEBEURTENISBUS`) | Jeugdhulp/-bescherming (thema Jeugd), uitgesplitst naar **kind van blijvend gezin** vs. **kind van instromend gezin** — toetst direct of de daling van de behoefte komt door instroom of door afname bij bestaande kinderen |
| Jongeren (15-24) | Uitstroom uit de buurt (vaak levensfase-gebonden; apart schatten t.o.v. niet-gentrificerende Oost-buurten om dat te corrigeren) | Bijstand/Uitkeringen, GGZ, medicijngebruik (psychofarmaca) |
| Alleenwonenden | Verhuisgeneigdheid (verwacht gevoeliger voor prijsstijging: één inkomen) | Armoede/schuld (ARMOEDE, SMALLE_SCHULD), Wmo/eenzaamheidsproxy |
| Aankomende senioren (45-64) | Verhuisgeneigdheid (laag verwacht; vermogenseffect via eigen woning mogelijk positief) | Mantelzorgpotentieel (`AFSTANDTOTKIND` uit thema Achtergrondkenmerken — blijft het kind in de buurt of juist niet?) |
| Ouderen (65+) | Verhuisgeneigdheid (laagst verwacht) | Wmo-gebruik, GGZ, sterfte (§5 punt 6) — juist **ondanks** blijven, op indirecte impact toetsen |
| Huishoudens/totaal | Samengestelde blijf/instroom/vertrek-decompositie (§ eerder besproken methode) | Stapelingsindex (§5 punt 2) |

**Methode:**
1. **Decompositie per doelgroep.** Voor elke leeftijdsgroep afzonderlijk: het
   aandeel blijvers/vertrekkers/instromers per buurt-jaar, en het verschil in
   de steunbehoefte-indicator tussen deze groepen (dezelfde shift-share-opzet
   als de algemene gentrificatie-decompositie, nu per doelgroep in plaats van
   voor de hele populatie).
2. **Interactiemodel.** Eén multilevel model per uitkomst, met een
   **doelgroep × gentrificatie-intensiteit-interactie**: toetst rechtstreeks
   of het effect sterker/eerder optreedt bij kinderen dan bij ouderen — de
   kern van de hypothese — in plaats van dit per doelgroep apart te
   veronderstellen.
3. **Kind-van-instromer vs. kind-van-blijver.** Specifiek voor kinderen: via
   de ouder (`KINDOUDERTAB`/`JURIDISCHE_OUDER_KIND_JEUGDZORG`) vaststellen of
   een kind bij een gezin hoort dat recent is ingestroomd; vergelijk
   jeugdhulpgebruik tussen beide groepen. Dit onderscheidt direct het
   "instroom-verdunningseffect" (NYC-bevinding) van een eventueel effect op
   de blijvende kinderen zelf.
4. **Doelgroep-tijdlijn als eindproduct.** Per doelgroep, per jaar: een
   gestapelde decompositie (blijvers/instromers/vertrekkers) plus de
   steunbehoefte-indicator, voor gentrificerende versus niet-gentrificerende
   Oost-buurten — vergelijkbaar in vorm met de bestaande Vooruitblik-tab,
   maar nu op empirisch persoonsniveau i.p.v. gebiedstrendextrapolatie.

**Disclosure-aandachtspunt:** doelgroep × buurt × jaar-uitsplitsingen maken
cellen snel klein; combineer zo nodig kinderen/jongeren tot bredere
leeftijdsklassen of rapporteer op wijk- in plaats van buurtniveau (§8).

## 7. R-werkwijze in de beveiligde omgeving (BMO)

CBS-microdatabestanden worden doorgaans als SPSS (`.sav`) of SAS
(`.sas7bdat`) aangeleverd; R is een toegestane taal in de BMO.

- **Inlezen:** `haven::read_sav()` / `read_sas()` per bestand;
  `data.table::fread()` alleen indien CBS het bestand als platte tekst
  aanlevert. Grote jaarbestanden (LBZ, MSZ) inlezen als `data.table` i.p.v.
  `data.frame` vanwege omvang en join-snelheid.
- **Koppelen:** joins op RINPERSOON(S) met `data.table`'s `merge`/`[]`-syntax
  (sneller en geheugenzuiniger dan `dplyr::*_join` bij bestanden met
  miljoenen rijen); persoon-jaar-panelen opbouwen met `rbindlist()` over de
  jaarbestanden vóór het samenvoegen met de regelingenbestanden.
- **Analyse:** `cluster`/`mclust` voor typologieën, `lme4`/`nlme` voor
  multilevel modellen, `survival`/`msm` voor trajectanalyse en
  transitiekansen, `broom`/`broom.mixed` voor overzichtelijke modeloutput
  die vervolgens tegen de disclosure-regels getoetst kan worden.
- **Visualisatie:** `ggplot2`, maar uitsluitend op **vooraf geaggregeerde**
  data (binned/gegroepeerd, nooit een scatter van individuele punten) —
  spreidingsdiagrammen met individuele stippen zijn niet toegestaan als
  output, ook niet gejitterd.
- **Scriptstructuur (aanbevolen):**
  `01_inlezen.R` → `02_populatie_en_koppeling.R` (basispopulatie Oost +
  joins) → `03_analyse.R` (per onderzoeksvraag uit §5) →
  `04_output_aggregatie.R` (enige script dat output produceert die de BMO
  verlaat; hierin expliciet de celgrootte- en dominantiecontroles uit §8
  inbouwen vóórdat iets wordt aangeboden voor outputtoetsing).
- Alle scripts versiebeheerd (bijv. lokaal git-archief buiten de BMO, code
  zelf bevat geen microdata en mag dus wel de omgeving in en uit).

## 8. Privacy, AVG en disclosure control

- **Werkomgeving:** uitsluitend in de beveiligde CBS Remote Access-omgeving;
  geen download van brongegevens, geen los internetverkeer tijdens een
  sessie.
- **Output-toetsing:** elke tabel/grafiek/modelresultaat die de omgeving
  verlaat wordt getoetst: minimaal 10 (ongewogen) eenheden per cel, geen
  dominante bijdrager >50% van een celtotaal, geen individuele sleutels
  (RIN) in output, modellen met minimaal 10 vrijheidsgraden.
- **Strengere regel voor inkomen/vermogen:** volgens het STAPMON-
  documentatierapport geldt hier een hogere drempel dan de algemene
  10-eenhedenregel — resultaten over inkomen/vermogen mogen pas gepubliceerd
  worden bij **minimaal 100 personen/huishoudens**, afgerond op honderdtallen;
  percentages alleen bij een noemer ≥100; gemiddelden/medianen/sommen alleen
  bij ≥100 waarnemingen én een grootste bijdrage van ≤30% aan de celsom. Dit
  raakt direct de ARMOEDE- en SMALLE_SCHULD-indicatoren uit §5 op
  buurtniveau in Oost.
- **Toestemming per thema.** Voor een deel van de STAPMON-thema's (Vektis/
  GGZ-zorgkosten, CAK/Wmo, WSW, Wlz, Jeugd, Halt, justitiële variabelen,
  Wsnp, Medicijn, Wanbetaler zorgverzekering, Doelgroepregister,
  Kinderopvangtoeslag, de smalle schulddefinitie, Aftrek bijzondere
  ziektekosten, Herkomstland) is naast de reguliere projectaanmelding ook
  aparte toestemming van de bronleverancier en/of CBS-vakafdeling nodig
  (§3.0) — dit kan de doorlooptijd van stap 0 in §9 verlengen.
- **Doelbinding:** project 9097 is al gericht op "gebruik over de
  regelingen heen", dus de bovenstaande bestanden vallen in beginsel binnen
  de bestaande doelomschrijving — een uitbreiding buiten dit thema (bijv.
  een heel ander onderwerp) zou wel een herbeoordeling vereisen.
- Kleine Oost-buurten kunnen, net als nu bij KWB, tot onderdrukte cellen
  leiden zodra een subgroep (bijv. "jeugdhulp + GGZ" in één buurt) onder de
  10 eenheden komt — hou hier in de analyseopzet (§5) rekening mee door
  primair op wijk- in plaats van buurtniveau te rapporteren, met buurtniveau
  als optionele verdieping waar de aantallen het toelaten.

## 9. Fasering

0. **STAPMON-thema's regelen onder 9097.** Bij CBS Microdata Services
   nagaan of Achtergrondkenmerken/Inkomen (nu onder project 10053) hergebruikt
   kunnen worden binnen 9097, en de overige benodigde thema's aanvragen
   (minimaal Uitkeringen, Wmo, Wlz, Jeugd, Gezondheid & Welzijn, Gezondheid &
   Medicijngebruik; optioneel Vermogen en schulden voor SMALLE_SCHULD en
   Rechtsbescherming en veiligheid voor de justitie-dimensie). Meteen ook de
   toestemmingsvereisten per thema (§3.0/§8) uitzoeken — sommige thema's
   vragen aparte bronleverancierstoestemming naast de reguliere aanvraag.
0b. **Vastgoed-/verhuisbestanden regelen onder 9097 of 9096.** Voor de
   gentrificatie-analyse (§6) nagaan of `BAGWOZTAB`, `EIGENDOMTAB`,
   `EIGENDOMWOZBAGTAB`, `GBAADRESGEBEURTENISBUS` en
   `LEVCYCLWOONNIETWOONBUS` (nu onder project 9096, §3.2) hergebruikt kunnen
   worden binnen 9097, of dat de gentrificatie-analyse als apart deelproject
   onder 9096 loopt.
1. **Bestandenlijst bevestigen** met de ahti-datamanager: DO-vraag oplossen
   (§3.1), nagaan welke jaarbestanden (LBZ/MSZ/ZVW) daadwerkelijk al zijn
   afgenomen binnen 9097 versus alleen geautoriseerd maar nog niet opgehaald.
2. **Basispopulatie en koppeling bouwen** (§4): Oost-populatie afbakenen,
   STAPMON-paneel + aanvullende regelingenbestanden samenvoegen.
3. **Pilot op één domein-combinatie** (aanbevolen: Wmo + GGZ bij 65-plussers,
   omdat dit al vergelijkbaar is met de bestaande RIVM-koppeling in de
   Dynamo-monitor) om de koppel- en analysepijplijn te valideren — te
   beginnen met STAPMON09 (WMO) plus de GGZ-detailbestanden uit §3.1.
4. **Opschalen** naar de overige regelingen en domeinen uit §5.
5. **Trajectanalyse en sterfte-koppeling** als verdiepingsslag, zodra de
   dwarsdoorsnede-analyses (2-4) staan.
6. **Gentrificatie-analyse per doelgroep (§6)**, zodra stap 0b is geregeld:
   blijf/vertrek/instroom-decompositie en het doelgroep ×
   gentrificatie-intensiteit-interactiemodel, te beginnen met de
   kinderen-doelgroep (toetst de besproken hypothese direct).

## 10. Risico's

1. **STAPMON-thema's staan nog onder het verkeerde project.** Achtergrond-
   kenmerken/Inkomen zijn gekoppeld aan project 10053, niet aan 9097 — dit
   moet eerst administratief worden rechtgezet/aangevraagd (§9, stap 0) vóór
   ze in dit onderzoek gebruikt mogen worden (doelbinding, §8).
2. **Toestemming per thema kan vertragen.** Verschillende thema's (Vektis/
   GGZ, CAK/Wmo, WSW, Wlz, Jeugd, justitie, Wsnp, Medicijn e.a.) vereisen
   aparte bronleverancierstoestemming (§3.0/§8) — dit is niet bij voorbaat
   geregeld met de bestaande projectmachtiging en kan de doorlooptijd van
   stap 0 verlengen.
3. **Onbevestigd bestand "DO".** Verifiëren vóór gebruik in het analyseplan
   (dit betreft het losse bestand uit §3.1, niet een STAPMON-thema).
4. **Disclosure control op kleine Oost-buurten**, met een striktere drempel
   voor inkomen/vermogen (≥100 eenheden, zie §8) dan de algemene 10-regel —
   raakt direct de ARMOEDE- en SMALLE_SCHULD-indicatoren op buurtniveau.
5. **Wmo-gegevens zijn niet landsdekkend.** De Wmo-data komen uit de
   vrijwillige gemeentelijke monitor sociaal domein (GMSD); niet elke
   gemeente levert elk jaar volledig aan — controleren of Amsterdam
   consistent en volledig heeft aangeleverd over de gewenste jaren.
6. **Trendbreuken binnen STAPMON zelf.** Onder meer GGZ (2022: DBC →
   zorgprestatiemodel, twee oude variabelen samengevoegd tot één), Wmo
   (CAK-detail stopt in 2020), vermogen (herziening 2017) en de
   armoede-/schulddefinities (2018/2019, met een latere definitiewijziging
   in 2021) — bij meerjarige trajectanalyse (§5, punt 5) hiermee rekening
   houden, niet zomaar als doorlopende reeks behandelen.
7. **Weging nodig voor steekproefvariabelen.** Onderwijsniveau
   (HBOPL/HGOPL/STARTKWALIFICATIE) en de gezondheidsenquête-variabelen
   (roken, alcohol, drugs, overgewicht, beweegnorm) zijn deels
   steekproefgebaseerd en vereisen weging (GEWICHTOPL resp.
   GEZGEWEindGewicht/GEZGEWCorrectieGewicht) — zonder weging niet
   representatief voor de hele Oost-populatie.
8. **Paneel-harmonisatie van de aanvullende bestanden.** MSZ/ZVW-bestanden
   uit §3.1 hebben jaarspecifieke versievarianten (bijv.
   `MSZPRESTATIESVEKTTAB2020V12020` vs. `MSZPRESTATIESVEKTTAB2021V12021`)
   met mogelijk wisselende variabelen/definities tussen jaren — relevant
   voor de aanvullende bestanden, niet voor STAPMON zelf.
9. **NIETVSLGWBTAB-personen.** Personen zonder GWB-koppeling (bijv.
   institutionele adressen) vallen buiten de buurtselectie; bepalen of dit
   een relevante uitval is voor de Oost-populatie (bijv. beschermd wonen).
10. **Vastgoed-/verhuisbestanden staan onder een ander project (9096).**
    Net als bij STAPMON moet de gentrificatie-analyse (§6) eerst een
    project-koppeling regelen vóór de bestanden uit §3.2 gebruikt mogen
    worden (§9, stap 0b).
11. **Kleine cellen bij doelgroep-uitsplitsing.** Doelgroep × buurt × jaar
    (§6) maakt cellen sneller klein dan een buurtbrede uitsplitsing —
    expliciet rekening houden met de drempels uit §8 bij het rapporteren
    per doelgroep.

## 11. Aanbeveling

Start met stap 0 (STAPMON-thema's regelen onder 9097) en stap 0b
(vastgoed-/verhuisbestanden regelen — 9096) parallel — beide bepalen hoeveel
van het analyseplan in §5/§6 direct uit bestaande koppelingen kan komen
versus apart aangevraagd moet worden. Bouw daarna de basispopulatie en
koppeling (stap 2) en valideer de aanpak met de pilot uit stap 3 (Wmo + GGZ
bij 65-plussers) voordat wordt opgeschaald naar alle domeinen, de
trajectanalyse en de gentrificatie-analyse per doelgroep (§6).

## Bronnen

- CBS, *Documentatierapport Stapelingsmonitor 2012-2024* (Microdataservices,
  2 december 2025) — §3.0.
- CBS, dienstencatalogus/richtlijnen microdata-output (disclosure- en
  publicatieregels) — §8.
- Boterman, W.R., *Gentrifiers Settling Down? Patterns and Trends of
  Residential Location of Middle-Class Families in Amsterdam*, Housing
  Studies 25(5), 2010 — "family gentrifiers"/"yupps", onderbouwing §6.
- Boterman, W.R., *Housing Liberalisation and Gentrification: The Social
  Effects of Tenure Conversions in Amsterdam*, Tijdschrift voor Economische
  en Sociale Geografie 105(2), 2014.
- NBER Working Paper 25809 / NYU Furman Center, *Does Gentrification
  Displace Poor Children? New Evidence from New York City Medicaid Data* —
  onderbouwing dat kinderarmoede-daling in gentrificerende buurten vooral
  via instroom loopt, niet via versnelde uitstroom van bestaande
  gezinnen (§6).
- *The Consequences of Gentrification and Displacement for Older Adults in
  the U.S.*, PMC6183414 — indirecte impact op ouderen ondanks lage
  verhuisgeneigdheid (§6).
- *Aging in Place in Gentrifying Neighborhoods: Implications for Physical
  and Mental Health*, PubMed 28958016 (§6).
- Sociale Vraagstukken, *Uitsluiting door gentrificatie* — "exclusionary
  displacement" in de Nederlandse sociale-huursector (§6).
