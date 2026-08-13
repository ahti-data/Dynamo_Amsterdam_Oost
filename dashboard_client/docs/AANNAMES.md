# Aannames & verantwoording — Dynamo Monitor Amsterdam Oost

**Opgesteld:** 10 juli 2026 (uitgebreid met 2016–2020 op verzoek) · **Team:** strategie-consultant (lead), data-analist, welzijnsdomein-specialist, geo-specialist, QA-specialist
**Bron:** CBS Kerncijfers Wijken en Buurten (KWB) 2016–2025 + CBS Toelichting variabelen KWB 2025. Jaargangen 2016–2020 gedownload van de CBS-reekspagina (kwb-2016.xls t/m kwb-2020.xlsx).

Dit document bevat **alle aannames en keuzes** die tijdens het bouwen van de monitor zijn gemaakt, geordend per fase. De belangrijkste staan ook in de tool zelf onder *Verantwoording*.

---

## 0. Dekking: gemeenten, gebieden en niveaus (uitbreiding juli 2026)

| # | Aanname | Onderbouwing / risico |
|---|---------|----------------------|
| 0.1 | De monitor dekt **35 gemeenten**: alle 32 gemeenten met ≥ 100.000 inwoners (KWB 2025) plus de drie Amsterdamse buurgemeenten Amstelveen, Diemen en Ouder-Amstel als regiocontext. Opent op **Amsterdam / stadsdeel Oost** — de thuisbasis van Dynamo. Uitbreiden = gemeentecode toevoegen aan `GEMEENTEN` in `build_data.py`, `fetch_geo.py` draaien, herbouwen. | De grens van 100.000 inwoners is een teamkeuze (grote gemeenten met genoeg wijken/buurten voor zinvolle analyse); de buurgemeenten zijn behouden voor de Amsterdamse context. |
| 0.2 | De **Amsterdamse gebiedsindeling** komt rechtstreeks uit de officiële gemeentelijke gebiedenregistratie (api.data.amsterdam.nl, GGW-indeling 24-3-2022): 9 stadsdelen (incl. Weesp als stadsgebied en Westpoort) en 25 GGW-gebieden. Elke CBS-wijk is **op code** (niet op naam) aan precies één gebied gekoppeld. | Bron: gemeentelijke API + onderzoek.amsterdam.nl. Weesp is formeel een "stadsgebied", hier als stadsdeel behandeld. |
| 0.3 | **Westpoort** (2 wijken, havengebied) valt officieel buiten de 25 GGW-gebieden en is toegevoegd als pseudo-gebied, zonder eigen kaartvlak op gebiedsniveau (wel in ranglijsten/tabellen). | Zo dekken de gebieden alle 110 wijken. |
| 0.4 | **Niveaus**: stadsdelen, gebieden, wijken en buurten (buiten Amsterdam: wijken en buurten). Stadsdeel- en gebiedstotalen zijn zelf geaggregeerd uit wijken (methode §4.1, drempel ≥ 80% van de wijken gevuld). Op stadsdeelniveau is er geen kaart (wel ranglijst/tabel). | Gebiedsgeometrie: maps.amsterdam.nl open geodata (WGS84). |
| 0.5 | **Historische koppeling buiten Oost**: Amsterdam wisselde in 2023 van wijkcodes. Voor Oost geldt de handmatig geverifieerde mapping (§1.2); voor de overige wijken en andere gemeenten wordt eerst op code en anders op **genormaliseerde naam** gekoppeld. Wijken/buurten zonder match tonen alleen recente jaren. Amsterdamse buurten kregen in 2022 grotendeels nieuwe codes én namen → buurttrends starten daar veelal in 2023. | Naam-koppeling buiten Oost is niet per wijk handmatig geverifieerd — steekproef via aggregaat-regressie (Oost 2024 identiek aan geverifieerde v1-waarde). |
| 0.6 | Zaanstad heeft in KWB 2025 meer buurten (79) dan de gebruikte geometrie-jaargang 2023 (50); buurten zonder kaartvlak verschijnen wel in ranglijsten en tabellen, niet op de kaart. Ouder-Amstel kent in de CBS-indeling slechts 1 wijk. | Geometrie is CBS-indeling 2023 (PDOK); bij een herindeling loopt de kaart achter op de data. |

## 1. Afbakening: wat is "Amsterdam Oost"?

| # | Aanname | Onderbouwing / risico |
|---|---------|----------------------|
| 1.1 | Stadsdeel Oost = de **15 CBS-wijken met code `WK0363MA` t/m `WK0363MQ`** (indeling 2023 e.v.): Oostelijk Havengebied, Weesperzijde, Oosterparkbuurt, Transvaalbuurt, Dapperbuurt, Indische Buurt-West/-Oost, Zeeburgereiland/Bovendiep, IJburg-West/-Oost/-Zuid, Frankendael, Middenmeer, Betondorp, Omval/Overamstel. | De letterprefix in de CBS-wijkcode volgt de Amsterdamse stadsdeelindeling (M = Oost). Weesp (S-codes) en Zuidoost (T-codes) vallen erbuiten. |
| 1.2 | De **oude CBS-indeling (2016–2022)** is per wijk **op naam gekoppeld** aan de nieuwe codes. Codes én namen van de 15 Oost-wijken zijn over de hele periode 2016–2022 identiek (empirisch geverifieerd per jaargang). Let op: de volgorde kruist (WK036329 Dapperbuurt → WK0363ME; WK036330 Transvaalbuurt → WK0363MD). | Geverifieerd door de data-analist: inwonertallen 2022 vs. 2023 wijken per wijk < 7% af → grenzen feitelijk ongewijzigd. |
| 1.3 | Uitzondering: **IJburg-Oost** groeide 2022→2023 met +176% (225 → 620 inwoners). Dit is **echte nieuwbouwgroei (Strandeiland)**, geen grenswijziging. Trends voor deze wijk zijn betrouwbaar maar klein-en-volatiel; veel indicatoren zijn er door het CBS onderdrukt. | Kleine aantallen: interpreteer IJburg-Oost met voorzichtigheid. |
| 1.4 | **Buurtniveau** (76 buurten binnen Oost) is opgenomen **alleen vanaf 2023 en alleen voor demografische indicatoren**. Buurtkoppeling met de oude indeling (2021/22) is niet gelegd — daarvoor is een aparte CBS-overgangstabel nodig. | Sociaaleconomische cijfers zijn op buurtniveau bij 13–26 van de 76 buurten onderdrukt → onbetrouwbaar beeld; wijkniveau is het primaire analysenniveau. |

## 2. Databeschikbaarheid & kwaliteit

| # | Aanname | Onderbouwing / risico |
|---|---------|----------------------|
| 2.1 | **KWB 2025 is een voorlopige levering**: inkomen, uitkeringen (`a_soz_*`), armoede, jeugdzorg, Wmo en opleiding zijn er volledig leeg. Voor die indicatoren geldt **2024 als laatste jaar**; de tool klemt het jaar automatisch en toont een melding. | CBS vult deze kolommen later aan; herbouw de dataset bij een nieuwe levering (zie §6). |
| 2.2 | Een indicator geldt als "beschikbaar" in een jaar wanneer **≥ 12 van de 15 wijken** een waarde hebben. Het Oost-totaal wordt dan berekend over de gevulde wijken; de samenstelling kan per jaar licht verschillen (bijv. Wmo 2021 zonder het onderdrukte IJburg-Oost, 2022+ mét). | Voorkomt dat een Oost-totaal op een handvol wijken leunt. Effect van de wisselende samenstelling is klein (IJburg-Oost: 70–1.535 inwoners), maar trends op het Oost-totaal kunnen er een sprongetje van enkele tientallen door bevatten. |
| 2.3 | CBS-aantallen op wijk-/buurtniveau zijn **afgerond op veelvouden van 5**; zorgcijfers 0–7 zijn geheim ('.'). Sommen van wijken tellen daardoor niet exact op tot stads- of landstotalen. | Afwijkingen van enkele tientallen op stadsdeelniveau zijn inherent aan de bron. |
| 2.4 | Parseerregels: `'.'` en lege cellen = ontbrekend; decimaal**komma's** omgezet naar punten; voorloopspaties en spaties in kolomnamen (2024) gestript; losse `','` (2022, gaskolom) = ontbrekend. | Bevindingen data-analist; zonder deze regels ontstaan stille fouten. |
| 2.5 | **Startjaren per indicatorgroep** (empirisch bepaald, ≥ 12/15 wijken gevuld): bevolking, huishoudens, uitkeringen (`a_soz_*`), inkomen (`g_ink_pi`, `p_hh_li`) vanaf **2016**; Wmo, jeugdzorg, mediaan vermogen en arbeidsparticipatie vanaf **2018**; opleidingsniveau vanaf **2019** (kolom `a_opl_lg`, zelfde indeling als latere `a_opl_bvm`); herkomst vanaf **2023**; armoede alleen **2024**. | De tool springt automatisch naar de dichtstbijzijnde beschikbare jaargang. Opleidingsgelijkstelling 2019/2020 = aanname op basis van gelijke kolomdefinitie; alleen 2021/22↔2023/24 is op landelijke totalen geverifieerd. |

## 3. Conceptbreuken in de CBS-reeksen

| # | Aanname | Gevolg in de tool |
|---|---------|-------------------|
| 3.1 | **Herkomst**: t/m 2022 "westers/niet-westers", vanaf 2023 "geboren in NL / Europa / buiten Europa". Niet vergelijkbaar. | Herkomstindicatoren tonen alleen 2023–2025; geen trend ervóór. |
| 3.2 | **Armoede**: `p_ink_ar`/`p_ink_ba` volgen de nieuwe CBS/Nibud/SCP-definitie en bestaan alleen voor verslagjaar 2024. | Voor trend gebruiken we het stabiele `p_hh_li` (aandeel huishoudens in landelijk laagste 40% inkomens; landelijk gemiddelde = 40%). |
| 3.3 | **Opleiding**: kolommen hernoemd in 2023 (`a_opl_lg/md/hg` → `a_opl_bvm/hvm/hw`), inhoudelijk identiek (geverifieerd op landelijke totalen). | Als één doorlopende reeks behandeld (2021–2024). |

## 4. Berekeningen

| # | Aanname | Toelichting |
|---|---------|-------------|
| 4.1 | **Stadsdeel Oost (totaal)** staat niet in de CBS-bestanden en is zelf geaggregeerd uit de 15 wijken: aantallen (`a_*`) gesommeerd; percentages en gemiddelden **gewogen naar inwoners** (huishoudens-indicatoren zoals `p_hh_li` naar huishoudens); huishoudensgrootte = inwoners ÷ huishoudens; bevolkingsdichtheid = inwoners ÷ teruggerekend landoppervlak. | Weging naar de exacte CBS-noemer (bijv. personen tot 23 jaar voor jeugdzorg) is niet mogelijk met de beschikbare kolommen; inwonerweging is de gangbare benadering. |
| 4.2 | **Mediaan vermogen Oost** = huishoudens-gewogen gemiddelde van wijkmedianen — wiskundig een **benadering** (medianen zijn niet optelbaar). | Alleen indicatief gebruiken op stadsdeelniveau; wijkwaarden zijn exact CBS. |
| 4.3 | Afgeleide aandelen zelf berekend: % 0–14, % 15–24, % 65+, % eenpersoonshuishoudens, % huishoudens met kinderen, % herkomst buiten Europa (teller/noemer uit dezelfde CBS-rij, ×100, 1 decimaal). | CBS levert deze aandelen niet als kolom. |
| 4.4 | Inkomen per inwoner en mediaan vermogen staan in de bron in **×€1.000** en zijn omgerekend naar euro's. | `26,4` in de bron = € 26.400. |
| 4.5 | **Relatieve weergave** = procentuele afwijking t.o.v. de gekozen referentie (Amsterdam of Oost-totaal). Voor **absolute aantallen is relatieve weergave uitgeschakeld** — een wijk afzetten tegen het stadstotaal is betekenisloos. | Advies welzijnsspecialist: absolute volumes tonen voor capaciteit, concentratie (relatief) alleen voor percentages/gemiddelden/dichtheden. |
| 4.6 | `p_geb`, `p_ste` en `p_wmo_t` zijn **per 1.000 inwoners** (promille), geen percentage. | In de tool weergegeven met ‰. |

## 5. Domeinkeuzes (koppeling aan Dynamo-diensten)

| # | Aanname | Toelichting |
|---|---------|-------------|
| 5.1 | Dynamo's dienstverlening is vertaald naar **7 thema's**: Basisdemografie (buurtwerk/Huizen van de Wijk), Jeugd & jongeren (jeugd-/jongeren-/kinderwerk), Ouderen & vergrijzing (ouderenwerk), Bestaanszekerheid & schuldhulp (maatschappelijke dienstverlening), Eenzaamheid & huishoudens (ontmoeting), Diversiteit & herkomst (taal/inburgering/sociaal raadslieden), Zorg & mantelzorg (mantelzorgondersteuning, welzijn op recept). | Gebaseerd op het publieke dienstenprofiel van Dynamo Amsterdam; niet met Dynamo gevalideerd — pas de thema-indeling aan als het aanbod anders is. |
| 5.2 | CBS-indicatoren zijn **proxies, geen vraagcijfers**: jeugdzorggebruik ≈ jeugdproblematiek; verweduwing/alleenwonen ≈ eenzaamheidsrisico; bijstand ≈ doelgroep schuldhulp; Wmo-gebruik ≈ mantelzorgdruk; laag opleidingsniveau ≈ laaggeletterdheid/formulierenhulp. | Signalen voor locatiekeuze, geen directe behoefteraming. |
| 5.3 | **45–64-jarigen** zijn opgenomen als "aankomende vergrijzing": de ouderen van over 10–20 jaar, relevant voor lange-termijn-locatiekeuze (een pand staat er 20 jaar). | Ontwikkelperspectief naast het huidige beeld. |
| 5.4 | Vergelijkingsadvies: weeg **absoluut volume** (waar wonen de meeste mensen uit de doelgroep) én **relatieve concentratie** (waar wijkt de wijk het sterkst af van Amsterdam/Oost). Een wijk met index 150 maar 200 ouderen is minder locatierelevant dan een wijk met index 110 en 2.000 ouderen. | Kern van het gebruik van de tool voor locatiestrategie. |
| 5.5 | Overwogen maar **bewust weggelaten**: ruwe proxies als "bijstand per 100 huishoudens" (teller personen, noemer huishoudens) en "verweduwden t.o.v. 65-plussers" (verweduwing komt ook < 65 voor). | Vermijdt schijnprecisie; de onderliggende kolommen zitten er wél in. |

## 6. Geo & techniek

| # | Aanname | Toelichting |
|---|---------|-------------|
| 6.1 | Kaartgeometrieën: **CBS Gebiedsindelingen 2023 (gegeneraliseerd)** via PDOK, gefilterd op de 15 Oost-wijken resp. 76 buurten, vereenvoudigd tot < 25 kB per bestand, WGS84. | Bedoeld voor vergelijking, niet voor exacte grensbepaling. |
| 6.2 | De tool is een **zelfstandige React 18 + TypeScript (Vite) applicatie** zonder runtime-afhankelijkheden van externe servers: eigen SVG-grafieken en -choropleth, zelf-gehoste fonts, data als statische JSON. Eén `npm run build` levert een map `dist/` die op elke webserver (nginx, Apache, IIS) of statische hosting draait. | Eis: "moet op een losse server kunnen draaien". Geen tracking, geen CDN's. |
| 6.3 | **Nieuwe CBS-jaargang verwerken**: leg het nieuwe `kwb*.xlsx` in de projectmap, voeg het toe aan `FILES` in `data-prep/build_data.py`, draai het script en herbouw de app. Kolomhernoemingen door CBS vergen mogelijk een regel in `RENAMES`. | Beheerprocedure; zie ook README. |
| 6.4 | Datakleuren komen uit een **CVD-gevalideerd palet** (kleurenblind-veilig, licht + donker thema); relatieve kaarten gebruiken een divergerende schaal (blauw ↔ rood) met neutraal midden. | Toegankelijkheid; getallen zijn altijd ook via tabel en tooltip beschikbaar. |

## 7. Aanvullingen na onafhankelijke review (10 juli 2026)

| # | Aanname/keuze | Toelichting |
|---|---------------|-------------|
| 7.1 | **Richting per indicator**: `hoog` (hogere waarde = sterker ondersteuningssignaal), `laag` (inkomen p.p., mediaan vermogen, arbeidsparticipatie) of `neutraal` (huishoudensgrootte, dichtheid, herkomst NL, huishoudens zonder kinderen). Ranglijsten, kaartkleuring en standaardselecties volgen deze richting. | De toewijzing is een inhoudelijke aanname van het team en is niet door Dynamo gevalideerd. |
| 7.2 | **Beschikbaarheid is dynamisch**: per combinatie van indicator × niveau × focusgebied bepaalt de tool welke jaren ≥ 60% gevulde gebieden hebben; keuzelijsten deactiveren onbeschikbare indicatoren en een afwijkend weergegeven jaar wordt altijd gemeld. | Vervangt de eerdere gemeentebrede jarenlijst die voor Oost te krap was (2016–2022 werd ten onrechte verborgen). |
| 7.3 | **Aggregaten**: minimaal 80% van de onderliggende wijken gevuld, met dekking (`members`) in het datamodel; gebieden met één wijk nemen het wijkcijfer over (dekking 1/1 wordt gemeld). **Mediaan vermogen wordt niet geaggregeerd** — medianen zijn niet optelbaar. | Reviewpunten 4 en 11. |
| 7.4 | **GGW-totalen zijn benaderingen** uit CBS-wijken. De officiële catalogus kent minimaal één wijk (Noordelijke IJ-oevers-West) die in twee GGW-gebieden ligt; deze tool telt elke wijk bij precies één gebied. Voor formele gebiedscijfers is het BBGA (Onderzoek & Statistiek Amsterdam) de aangewezen bron. | Reviewpunt 10. |
| 7.5 | **Kaartschaal vast over jaren** (absolute modus): de kleurgrenzen worden over alle beschikbare jaren van de selectie bepaald, zodat dezelfde kleur in elk jaar hetzelfde betekent. Klassegrenzen blijven data-gedreven (min–max), niet normatief. | Reviewpunt 19; normatieve grenzen vergen keuzes met Dynamo. |
| 7.6 | **Dekking**: 35 gemeenten (alle ≥ 100.000 inwoners + 3 Amsterdamse buurgemeenten), zichtbaar in de footer. Geometrie volgt de CBS-indeling **2025** via `fetch_geo.py`, passend bij de regiocodes van KWB 2025. | Reviewpunt 20; uitbreiding via README-procedure. |
| 7.7b | **Jaar-op-jaar koppeling buiten Amsterdam** — kritieke bevinding uit q-review2. Enkele gemeenten (Zoetermeer, Diemen) hebben bij een herverkaveling dezelfde CBS-wijk-/buurtcode voor een *ander* gebied hergebruikt. `find_row` vertrouwt een codematch daarom alleen als de genormaliseerde gebiedsnaam gelijk is aan de nieuwste jaargang; anders volgt naamkoppeling, of blijft de cel leeg. Zo krijgt geen enkel gebied de historie van een ander gebied. Een regressietest (`check_data.py`) bewaakt dit over alle 35 gemeenten (0 wijk-spookbreuken). | Voorheen leverde de blinde codematch onjuiste trends voor o.a. Zoetermeer. |
| 7.7c | **RIVM-dekking per gemeente verschilt.** RIVM 50150NED volgt indeling 2024; waar een gemeente in 2025 een code voor een ander gebied hergebruikte, wordt die code **niet** met RIVM gematcht (anders koppelt de uitkomst aan de verkeerde geografie). Gevolg: Zoetermeer heeft daardoor geen RIVM-uitkomsten (te veel hergebruikte codes); enkele gemeenten missen een handvol buurten. De claim "codes matchen exact" in §9.1 geldt primair voor Amsterdam. | q-review2 DATA-3. |
| 7.7 | De tool is een **signalerings- en verkenningsinstrument**, geen locatieadviesmodel: er is geen clusteralgoritme of locatiescore. Vraag- en aanbodgegevens (eigen locaties, bereik, capaciteit, vastgoed, prognoses) zijn bewust nog niet opgenomen. | Reviewpunten 5–8; zie docs/REVIEW-VERWERKING.md voor de backlog. |

## 8. Gentrificatie-analyse

| # | Aanname/keuze | Toelichting |
|---|---------------|-------------|
| 8.1 | **Definitie**: de gentrificatie-index combineert vier CBS-signalen over een instelbare periode — stijgende WOZ-waarde (`g_wozbag`, +), stijgend inkomen per inwoner (`g_ink_pi`, +), krimpend aandeel corporatiewoningen (`p_wcorpw`, −) en dalend aandeel lage inkomens (`p_hh_li`, −). | Klassieke operationalisatie van gentrificatie: stijgende woningwaarde + instroom hogere inkomens + krimpende betaalbare voorraad + verdringing lage inkomens. Configuratie staat in `GENTRIFICATION` in `build_data.py`. |
| 8.2 | **Standaardisatie**: per component wordt de verandering over de periode berekend (WOZ/inkomen als %-verandering, aandelen als procentpunt-verschil), daarna z-gestandaardiseerd t.o.v. de andere gebieden op hetzelfde niveau en vermenigvuldigd met de richting (+/−). De index is het **gemiddelde van de beschikbare component-z-scores**. | Relatieve maat: positief = gentrificeert sneller dan het gemiddelde gebied op dat niveau. Geen absolute norm en **geen bewijs van individuele verdringing**. |
| 8.3 | **WOZ-reeks** is samengesteld uit `g_woz` (t/m 2019) en `g_wozbag` (vanaf 2020); geverifieerd continu over de breuk (Amsterdam 2019→2020: ratio 1,13, geen methodesprong). | Maakt een 10-jaars WOZ-trend mogelijk. |
| 8.4 | **Woning-gewogen aggregatie**: WOZ en woningtype-aandelen worden op stadsdeel-/gebiedsniveau gewogen naar het aantal woningen (`a_woning`), niet naar inwoners. | Correcte noemer voor woningmarktindicatoren. |
| 8.5 | **Buurtniveau**: WOZ, koopwoningen, corporatiewoningen en lage inkomens zijn op buurtniveau redelijk gevuld (~78%) en toegevoegd aan de buurt-allowlist; inkomen per inwoner is er sterk onderdrukt (~37%) en telt alleen mee waar aanwezig. De standaardperiode kiest de breedste reeks waarin **alle vier** componenten bestaan, zodat kaart én verdringingsdiagram gevuld zijn. | De index rekent per gebied met de beschikbare componenten (coverage zichtbaar). |
| 8.6 | **Alle geo-niveaus**: de analyse werkt op stadsdelen, gebieden, wijken en buurten. Buiten Amsterdam en voor heel-Amsterdam-brede historie is de reeks korter (wijkhercodering 2023), waardoor de periode automatisch naar de beschikbare jaren krimpt. | Amsterdam-Oost heeft de rijkste reeks (2016–2024, alle componenten). |

## 9. Externe data & samenhang-analyse (gezondheid × socio-demografie)

**Bron:** de map `external-data/` bevat een reproduceerbare inventarisatie (download via `external-data/download_sources.py`, catalogus in `external-data/DATA_CATALOGUS.md`). De download was al aanwezig; er is niets opnieuw gedownload. Van de ~18 bronnen is er één geïntegreerd in de tool (zie 9.1); de rest is bewust nog niet opgenomen (9.5).

| # | Aanname/keuze | Toelichting |
|---|---------------|-------------|
| 9.1 | **Geïntegreerd: RIVM Gezondheid per wijk en buurt (50150NED)** als uitkomstenlaag (Y). 20 indicatoren over 7 domeinen (ervaren gezondheid, mentaal, eenzaamheid & sociaal, zorg/mantelzorg, bestaanszekerheid-beleving, leefstijl, leefomgeving), geselecteerd door het gezondheidsdomein-team (`data-prep/rivm_outcome_spec.json`). | Voor Amsterdam matchen de codes exact (indeling 2024 = 2023+); dekking daar ~95% wijk, ~80% buurt. Buiten Amsterdam varieert de dekking en worden hergebruikte codes overgeslagen — zie §7.7c. |
| 9.2 | **Gemodelleerde schattingen**: RIVM 50150 zijn kleine-gebiedsschattingen (18+, centrale schatting), geen directe metingen. Elke uitkomst draagt `estimateType: gemodelleerd` en wordt in de UI zo gelabeld. | Ruimtelijke smoothing kan verbanden gladstrijken; mogelijke circulariteit als het RIVM-model zelf SES-covariaten gebruikt. |
| 9.3 | **Jaaras**: RIVM-meetjaren zijn 2012/2016/2020/2022/2024. 2012 valt buiten de tool-jaaras (2016–2025) en vervalt; de overige worden op de tool-as geplaatst, tussenliggende jaren blijven leeg. Overlap met socio-demografie voor de tijdlijn: **2016, 2020, 2022, 2024**. | Per indicator verschilt de dekking (sommige alleen 2022–2024 of 2024); de tool toont alleen jaren met ≥60% gevulde wijken. |
| 9.4 | **Aggregatie naar stadsdeel/gebied**: inwoner-gewogen gemiddelde van de wijk-percentages (RIVM-percentages zijn van 18+; inwoners is een benaderende weging). Op wijk- en buurtniveau zijn het de native RIVM-waarden. Op buurtniveau zijn de uitkomsten toegevoegd aan de allowlist (registerachtige dekking ~80%). | De samenhang-analyse gebruikt bij voorkeur wijk/buurt (native), niet de aggregaten. |
| 9.5 | **Bewust nog niet geïntegreerd**: SES-WOA, Vektis-Wmo, CBS sociaal domein/Wmo/jeugdzorg, Leefbaarometer, BBGA, nabijheid voorzieningen, en de Amsterdamse aanbod-/sportlagen. Reden: (a) vermijden van dubbeltelling van dezelfde SES-factor, (b) licentie-onzekerheid (Vektis, BBGA), (c) aanbodlagen zijn geen uitkomstmaat, (d) scope. | Volgende fase; de socio-demografische X-set uit CBS KWB is al rijk genoeg voor de correlatie-analyse. |
| 9.6 | **Correlatiemethode**: Spearman-rangcorrelatie standaard (robuust bij begrensde/schuine percentages, uitschieters en kleine N), Pearson optioneel. Pairwise complete deletion; onderdrukt/leeg ≠ nul. n < 8 → geen coëfficiënt; 8–11 indicatief. 95%-BI via Fisher-z; p via t-benadering, expliciet als verkennend gelabeld (ruimtelijke autocorrelatie + multiple testing maken p te optimistisch). | Zie `docs/CORRELATIE-ONTWERP.md` voor de volledige onderbouwing. |
| 9.7 | **Ecologische correlatie**: alle samenhang is over gebiedsgemiddelden, geen individueel of causaal verband. Permanente waarschuwing in de view. Alleen relatieve X-variabelen (%/gemiddelden), nooit absolute aantallen (die correleren met gebiedsomvang → schijncorrelatie). | Kernregel uit de datacatalogus. |
| 9.8 | **Licentie**: RIVM 50150 is CC BY 4.0 (bronvermelding RIVM/CBS). Bij externe publicatie de licenties van alle bronnen opnieuw controleren (zie catalogus). | De tool toont de bron in de footer. |

## 10. Doelgroepdossiers (Inzichten-tabblad) — multivariate methode

| # | Aanname/keuze | Toelichting |
|---|---------------|-------------|
| 10.1 | De 25 inzichten (5 per Dynamo-activiteit) zijn **meer-dimensionale doelgroepdossiers**, niet losse enkelvoudige waarnemingen. Elk dossier definieert een precieze doelgroep (persona), een sociaal-demografisch profiel van 3–6 dimensies, en een multivariate koppeling aan zorg-/welzijns-/gezondheidsuitkomsten. | Vervangt de eerdere enkelvoudige inzichten ("wijk X is het jongst"), die als te simpel werden beoordeeld. |
| 10.2 | **Multivariate fundament** (`data-prep/multivar_foundation.json`, gegenereerd door `multivar_foundation.py`): op **416 Amsterdamse buurten** (2024) zijn berekend: (a) **k-means-buurttypologieën** (k=4, gekozen via silhouette 0,254) op 14 gestandaardiseerde dimensies; (b) **11 meervoudige lineaire regressies** per uitkomst (R² 0,85–0,94) met gestandaardiseerde coëfficiënten; (c) **22 partiële correlaties** (residuenmethode) die schijnverbanden ontmaskeren; (d) **16 composiet-z-indices** vs uitkomsten. Tools: numpy/sklearn. Élke in de dossiers geciteerde statistiek is herleidbaar tot dit bestand. | Bevindingen toegespitst op de 57 Oost-buurten met volledige dekking. **Belangrijk voorbehoud:** de 14 predictoren zijn zwaar collineair (VIF tot ~50), dus de gestandaardiseerde beta's zijn **geen** onafhankelijke, causale "drivers" — tekenomkeringen kunnen artefact zijn. De UI toont dit als prominent statistisch voorbehoud (`Inzichten.tsx`). |
| 10.2b | **Silhouette k=4 = 0,254** (zwakke clusterstructuur; k=3 geeft 0,238, k=5 0,244). De typologie is een ordeningshulpmiddel, geen scherp afgebakende indeling. | Clusternummering: 0 = gezinnen/koopwoningen, 1 = studenten/starters, 2 = gemengd (grootste), 3 = migrant-armoede. Persona- en method-velden in `insights.json` verwijzen consistent naar deze nummers. |
| 10.6 | **Circulariteit:** de RIVM-uitkomsten zijn zelf (mede) gemodelleerd uit socio-demografie die hier ook als voorspeller dient; de hoge R² is daardoor deels ingebouwd. Elk dossier benoemt dit expliciet in zijn aannames, plus een globale UI-notice. | Lees verbanden als ecologische samenhang, niet als bewezen oorzaak. |
| 10.7 | **Auteurschap:** de dossierteksten in `insights.json` zijn **automatisch gegenereerd** (taalmodel op basis van de databundel), geen werk van een menselijk expertteam; de UI vermeldt dit expliciet. De getallen zijn geverifieerd tegen het fundament. | Lees als onderbouwd startpunt, niet als vastgesteld feit. |
| 10.3 | **Inkomen op buurtniveau**: `g_ink_pi` en `m_hh_ver` zijn op buurtniveau te sterk onderdrukt (28/76 resp. 0/76) en zijn in de multivariate analyse vervangen door `p_hh_li` (aandeel lage inkomens) als inkomens-proxy. | Voorkomt modellen op te dunne data. |
| 10.4 | Nieuw afgeleid en op buurtniveau beschikbaar gemaakt: **`p_verwed`** (verweduwd, a_verwed/a_inw×100) en **`p_gesch`** (gescheiden), omdat verweduwing/scheiding sterke eenzaamheidsvoorspellers zijn en de experts ze multivariaat gebruikten. | Ook toegevoegd aan het thema Eenzaamheid. |
| 10.5 | **Ecologisch voorbehoud (hard):** alle uitkomsten zijn RIVM-**gemodelleerde buurtgemiddelden**; de verbanden zijn ecologisch (op buurtniveau) en mogen niet 1-op-1 op individuen worden toegepast (ecological fallacy). De dossiers benoemen dit expliciet en linken naar de onderliggende analyse zodat de gebruiker het zelf kan navorsen. | Signalerend, niet causaal of individueel. |

## 11. Vooruitblik (demografische prognose)

Toegevoegd juli 2026, methode volledig vervangen augustus 2026. Het tabblad
**Vooruitblik** toont de omvang van Dynamo-doelgroepen richting 2026–2055.
Tot aug. 2026 deed dit zelf een trendextrapolatie; dat eigen model is op
verzoek van de opdrachtgever **volledig verwijderd** ("te naïef": geen
demografische drivers, liet overal een getal zien ook waar dat weinig
voorstelde) en vervangen door **uitsluitend officiële gemeentelijke
puntprognoses**. Volledige verantwoording: **`docs/VOORUITBLIK-TEAM.md`**
(§3 = de verwijderde methode, ter archief; §4 = de huidige).

| # | Aanname/keuze | Toelichting |
|---|---------------|-------------|
| 11.1 | **Geen eigen model.** `dashboard/src/lib/forecast.ts` toont een prognosepunt alleen waar `officialForecast` (uit `data-prep/official_forecast.py`) een waarde heeft; anders expliciet geen punt. Geen shrinkage, demping, raking of band — die machinerie is verwijderd, niet uitgeschakeld. | Zie `docs/VOORUITBLIK-TEAM.md` §3 voor wat er was en waarom het is vervangen; git-commits `eeeee0e` (origineel) en `d9d9426` (tussenstap) bevatten de oude code. |
| 11.2 | **Twee officiële bronnen, elk voor wat ze uniek toevoegen.** O&S-bevolkingsprognose 2026 (Excel) → `a_00_14`/`a_15_24`/`a_45_64`, **alleen stadsdeel Oost + zijn 15 wijken**. BBGA (al gedownload voor de catalogus) → `a_inw`/`a_65_oo` (`BEV_PROG`/`BEV65PLUS_PROG`), **heel Amsterdam** (gemeente/stadsdeel/gebied/wijk, via `gebiedcode15` opgelost met `gebieden_amsterdam.json`). | Zie `docs/VOORUITBLIK-TEAM.md` §4 en `data-prep/official_forecast.py`. |
| 11.3 | **Blijvende, structurele gaten in dekking**: `a_1p_hh`/`a_hh` hebben in geen van beide bronnen een prognosevariabele (overal geen prognose); geen enkele bron publiceert op buurtniveau; geen bron dekt gemeenten buiten Amsterdam. `views/Vooruitblik.tsx` toont dat als expliciete lege staat, niet als afgeleid of geschat getal. | Bewuste keuze: "geen prognose" is eerlijker dan "een afgeleide prognose" waar geen bron zelf publiceert. |
| 11.4 | **Geen onzekerheidsband**: geen van beide bronnen publiceert een interval of hoog/laag-scenario (gecontroleerd in de BBGA-metadata). Een verzoek om O&S's eigen interval is uitgezet; zolang dat er niet is, toont de tool alleen het punt. | Schijnzekerheid over een controleerbaar officieel getal is erger dan geen band tonen — zelfde principe als de rest van deze catalogus. |
| 11.5 | **Horizon = alle jaren met dekking**: 2026, 2030, 2035, 2040, 2050, 2055 (`HORIZONS` in `forecast.ts`). | Voorheen beperkt tot 2030/2035 (het bereik van het oude trendmodel); nu simpelweg elk jaar dat een bron publiceert. |

---

*Wijzigingen op deze aannames? Pas `data-prep/build_data.py` (data), `dashboard/src/views/Verantwoording.tsx` (tekst in de tool) en dit document samen aan. Draai na iedere databuild `python data-prep/check_data.py`.*
