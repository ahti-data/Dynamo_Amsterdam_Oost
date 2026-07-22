import type { Dataset } from '../types'
import type { AppState } from '../App'
import { BronLink } from '../components/BronLink'

export function Verantwoording({ ds, state }: { ds: Dataset; state: AppState }) {
  return (
    <div className="prose">
      <h1 className="view-title">Verantwoording & aannames</h1>
      <p className="view-sub">
        Alle keuzes die het analyseteam heeft gemaakt bij het bouwen van deze monitor. Volledige
        technische details staan in <code>docs/AANNAMES.md</code> in de projectmap.
      </p>

      <div className="note">
        <strong>Kern in één zin:</strong> deze monitor toont CBS-cijfers (
        <BronLink state={state} id="cbs-kwb">Kerncijfers Wijken en Buurten 2016–2025</BronLink>)
        aangevuld met gemodelleerde{' '}
        <BronLink state={state} id="rivm-gezondheid">RIVM-gezondheidsuitkomsten</BronLink>, voor
        meerdere gemeenten en alle Amsterdamse gebiedsniveaus, thematisch geordend naar de
        dienstverlening van Dynamo — als signalerings- en verkenningsinstrument, geen
        locatieadviesmodel. Alle bronnen met hun vindplaats staan op het tabblad{' '}
        <BronLink state={state}>Bronnen</BronLink>.
      </div>

      <h2>Afbakening</h2>
      <ul>
        <li>
          De monitor dekt <strong>35 gemeenten</strong> (alle gemeenten met ≥100.000 inwoners, plus
          Amstelveen, Diemen en Ouder-Amstel als kleinere Amsterdamse buurgemeenten — uitbreidbaar
          via de datapijplijn, zie <code>data-prep/build_data.py</code>) en opent op{' '}
          <strong>Amsterdam, stadsdeel Oost</strong>: de thuisbasis van Dynamo, 15 CBS-wijken met
          code <code>WK0363M*</code>.
        </li>
        <li>
          Voor Amsterdam is de <strong>officiële gebiedsindeling</strong> opgenomen: 9 stadsdelen
          (incl. Weesp en Westpoort) en de 25 GGW-gebieden (gebiedsgericht werken, indeling
          24-3-2022), rechtstreeks uit de{' '}
          <BronLink state={state} id="amsterdam-gebieden">gemeentelijke gebiedenregistratie</BronLink>{' '}
          (api.data.amsterdam.nl) — elke wijk is op code aan precies één gebied gekoppeld.
          Westpoort valt officieel buiten de 25 gebieden en is als apart focusgebied toegevoegd
          (zonder eigen kaartvlak op gebiedsniveau).
        </li>
        <li>
          Cijfers zijn te bekijken op vier niveaus: <strong>stadsdelen, gebieden, wijken en
          buurten</strong> (buiten Amsterdam: wijken en buurten). Stadsdeel- en gebiedstotalen
          zijn zelf geaggregeerd uit de onderliggende wijken.
        </li>
        <li>
          Amsterdam wisselde in 2023 van CBS-wijkcodes. Historische jaren (2016–2022) zijn
          gekoppeld: voor Oost via een <em>handmatig geverifieerde</em> code-mapping
          (inwonertallen 2022→2023 wijken &lt; 7% af), voor de rest van de stad en andere
          gemeenten eerst op code en anders op <em>genormaliseerde naam</em>. Gebieden zonder
          match tonen alleen recente jaren. Uitzondering in Oost:{' '}
          <strong>IJburg-Oost</strong> groeide +176% door nieuwbouw (Strandeiland) — echte groei,
          geen grenswijziging.
        </li>
        <li>
          <strong>Buurtniveau</strong> is alleen betrouwbaar voor demografische indicatoren;
          sociaaleconomische cijfers worden op buurtniveau te vaak door het CBS onderdrukt om
          bruikbaar te zijn. Amsterdamse buurten kregen in 2022 grotendeels nieuwe codes én namen,
          dus buurttrends starten daar veelal in 2023.
        </li>
      </ul>

      <h2>Databeschikbaarheid</h2>
      <ul>
        <li>
          <strong>KWB 2025 is een voorlopige levering.</strong> Inkomen, uitkeringen, armoede,
          jeugdzorg, Wmo en opleiding zijn daarin nog leeg; voor die indicatoren is{' '}
          <strong>2024 het laatste jaar</strong>. De tool klemt het jaar dan automatisch en meldt
          dit.
        </li>
        <li>
          Niet elke indicator bestaat in alle jaargangen: bevolking, huishoudens, uitkeringen en
          inkomen lopen vanaf 2016; Wmo, jeugdzorg, mediaan vermogen en arbeidsparticipatie vanaf
          2018; opleidingsniveau vanaf 2019; herkomst vanaf 2023; armoede alleen 2024. De tool
          springt automatisch naar de dichtstbijzijnde beschikbare jaargang.
        </li>
        <li>
          Aantallen op wijk-/buurtniveau zijn door het CBS afgerond op veelvouden van 5; zorgcijfers
          met waarden 0–7 zijn geheim. Sommen van wijken tellen daardoor niet exact op tot het
          gemeentetotaal.
        </li>
        <li>
          Een indicator geldt als &quot;beschikbaar&quot; in een jaar wanneer minstens 80% van de
          wijken van de gemeente een waarde heeft; aggregaten worden over de gevulde wijken
          berekend, waardoor de samenstelling per jaar licht kan verschillen (klein effect).
        </li>
      </ul>

      <h2>Conceptbreuken in de CBS-reeksen</h2>
      <ul>
        <li>
          <strong>Herkomst</strong>: t/m 2022 hanteerde het CBS westers/niet-westers; vanaf 2023
          geboren-in-NL/Europa/buiten-Europa. Herkomstindicatoren tonen daarom alleen 2023–2025.
        </li>
        <li>
          <strong>Armoede</strong>: de indicatoren &quot;personen in armoede&quot; volgen de nieuwe
          CBS/Nibud/SCP-definitie en bestaan alleen voor 2024. Voor trend gebruiken we het stabiele
          &quot;huishoudens in laagste 40% inkomens&quot;.
        </li>
        <li>
          <strong>Opleidingsniveau</strong>: kolommen zijn in 2023 hernoemd
          (<code>a_opl_lg</code> → <code>a_opl_bvm</code>); inhoudelijk identiek, geverifieerd op
          landelijke totalen, en daarom als één reeks behandeld.
        </li>
      </ul>

      <h2>Richting van indicatoren</h2>
      <ul>
        <li>
          Elke indicator heeft een <strong>richting</strong>: bij de meeste betekent een hogere
          waarde een sterker ondersteuningssignaal, maar bij inkomen per inwoner, mediaan vermogen
          en arbeidsparticipatie is juist een <em>lage</em> waarde het signaal. Ranglijsten sorteren
          op het sterkste signaal en de kaart kleurt donker waar het signaal het sterkst is (bij
          &quot;laag&quot;-indicatoren wordt de kleurschaal dus omgekeerd, met uitleg in de legenda).
        </li>
        <li>
          Neutrale indicatoren (huishoudensgrootte, dichtheid, herkomst Nederland, huishoudens
          zonder kinderen) hebben geen eenduidige relatie met behoefte; die sorteren op hoogste
          waarde met een neutraal label.
        </li>
      </ul>

      <h2>Samenhang-analyse (gezondheid &amp; welzijn)</h2>
      <ul>
        <li>
          Het tabblad <strong>Samenhang</strong> toont de correlatie tussen socio-demografische
          gebiedskenmerken (X, uit CBS) en <strong>zorg-/welzijns-/gezondheidsuitkomsten</strong>{' '}
          (Y, uit{' '}
          <BronLink state={state} id="rivm-gezondheid">RIVM &quot;Gezondheid per wijk en buurt&quot; 50150NED</BronLink>): ervaren gezondheid,
          mentaal welzijn, eenzaamheid, mantelzorg, bestaanszekerheid-beleving en leefstijl. De
          RIVM-cijfers zijn <strong>gemodelleerde kleine-gebiedsschattingen</strong> (meetjaren
          2016, 2020, 2022, 2024), geen directe metingen.
        </li>
        <li>
          De samenhang wordt berekend <strong>over de gebieden</strong> binnen de gekozen focus en
          niveau (bijv. de 15 wijken van Oost of de 76 buurten), per meetjaar én over de tijd.
          Standaard <strong>Spearman-rangcorrelatie</strong> (robuust bij percentages, uitschieters
          en kleine N); Pearson optioneel. Getoond worden coëfficiënt, aantal gebieden (n) en het
          95%-betrouwbaarheidsinterval.
        </li>
        <li>
          <strong>Dit is een ecologisch, verkennend verband</strong> tussen gebiedsgemiddelden —
          geen individueel of causaal bewijs (ecologische drogreden). Meerdere sterke verbanden met
          inkomen, opleiding of armoede meten deels dezelfde onderliggende factor en tellen niet als
          onafhankelijke bewijzen. Bij kleine N is het interval breed; kies dan buurtniveau of een
          ruimere focus.
        </li>
      </ul>

      <h2>Gentrificatie-analyse</h2>
      <ul>
        <li>
          De <strong>gentrificatie-index</strong> combineert vier CBS-signalen over een instelbare
          periode: stijgende <strong>WOZ-waarde</strong>, stijgend <strong>inkomen per inwoner</strong>,
          krimpend aandeel <strong>corporatiewoningen</strong> en dalend aandeel{' '}
          <strong>lage inkomens</strong> (verdringing). Elk signaal wordt gestandaardiseerd (z-score)
          t.o.v. de andere gebieden op hetzelfde niveau; de index is het gemiddelde van de
          beschikbare componenten. Positief = het gebied verandert sneller dan gemiddeld in de
          richting van gentrificatie.
        </li>
        <li>
          Het is een <strong>relatieve, signalerende maat</strong>, geen bewijs van individuele
          verdringing: de index vergelijkt gebieden onderling, niet met een absolute norm. Het
          verdringingsdiagram (WOZ-stijging × verandering aandeel lage inkomens) toont het patroon
          per gebied; rechtsonder = prijzen omhoog én lage inkomens omlaag.
        </li>
        <li>
          De WOZ-reeks is samengesteld uit <code>g_woz</code> (t/m 2019) en <code>g_wozbag</code>{' '}
          (vanaf 2020); die lopen continu door. Op <strong>buurtniveau</strong> is inkomen sterk
          door het CBS onderdrukt — daar rekent de index met de wél beschikbare signalen (WOZ,
          sociale huur, lage inkomens). Werkt op alle niveaus; het rijkst voor Amsterdam op
          wijk-/gebiedsniveau (10 jaar historie in Oost).
        </li>
      </ul>

      <h2>Vooruitblik (prognose)</h2>
      <ul>
        <li>
          Het tabblad <strong>Vooruitblik</strong> trekt de omvang van Dynamo-doelgroepen
          (65-plus, 0–14, 15–24, alleenwonenden, 45–64, huishoudens, totaal inwoners) door naar{' '}
          <strong>2030 en 2035</strong>, per stadsdeel, gebied, wijk of buurt. Het is een{' '}
          <strong>trenddoortrekking</strong> op de CBS-reeks 2016–2025 — nadrukkelijk geen officiële
          bevolkingsprognose van CBS/PBL of Primos.
        </li>
        <li>
          <strong>Methode</strong> (opgesteld door de sociaal-demograaf van het team):{' '}
          <em>log-lineaire trendextrapolatie</em> per doelgroep per gebied (multiplicatief, blijft
          niet-negatief), met vier correcties: (1) <strong>shrinkage</strong> van de groeivoet naar
          het bovenliggende gebied — kleine, ruizige of korte buurtreeksen leunen zwaarder op de
          robuustere wijk/stadsdeel-trend (omvang-gewogen, James-Stein-idee); (2){' '}
          <strong>demping</strong> van de groeivoet over de horizon (0,9 per stap), zodat groei niet
          oneindig doorloopt; (3) een <strong>plausibiliteitsgrens</strong> van ±6% per jaar; en (4){' '}
          <strong>top-down raking</strong>, zodat de sub-gebieden optellen tot de (onafhankelijk
          geprognosticeerde) omvang van het focusgebied.
        </li>
        <li>
          <strong>Hamilton–Perry en cohort-component</strong> zijn bewust <em>niet</em> gebruikt: de
          CBS-leeftijdsklassen zijn ongelijk van breedte en sluiten niet op een projectiestap aan, en
          vitale statistieken (geboorte/sterfte/migratie) ontbreken op buurtniveau. Ze dienen hooguit
          als plausibiliteitscheck op stadsdeelniveau.
        </li>
        <li>
          De <strong>onzekerheidsband</strong> (±68%) komt uit de historische trendruis (residuen van
          de fit) en verbreedt met de wortel van de horizon; hij is ruimer voor kleine gebieden die
          sterk op de parent leunen. <strong>De betrouwbaarheid neemt af naar 2035 en op fijner
          niveau.</strong> De leeftijdsopbouw toont de 25–44-groep als <em>restpost</em> (totaal −
          overige klassen), een afgeleide en dus ruizige grootheid.
        </li>
        <li>
          <strong>Voorbehoud.</strong> Geen geplande nieuwbouw, sloop of beleidswijziging is
          meegenomen — nieuwbouwgebieden (IJburg, Zeeburgereiland, Oostelijk Havengebied) lopen
          daardoor vaak tegen de groeigrens aan. Cijfers zijn gebiedsgemiddelden (ecologisch
          voorbehoud): een prognose stuurt <em>waar</em> je capaciteit verschuift, niet <em>wie</em>{' '}
          precies wordt bereikt. Gebruik de vooruitblik als richtinggevend signaal, naast
          gemeentelijke prognoses en lokale kennis.
        </li>
      </ul>

      <h2>Berekeningen</h2>
      <ul>
        <li>
          <strong>Stadsdeel- en gebiedstotalen</strong> staan niet in de CBS-bestanden en zijn zelf
          geaggregeerd uit de wijken: aantallen gesommeerd; percentages en gemiddelden gewogen naar
          inwoners (huishoudens-indicatoren naar huishoudens); dichtheid via teruggerekend
          landoppervlak; minimaal 80% van de wijken gevuld. Het <em>mediaan vermogen</em> wordt
          bewust <strong>niet</strong> geaggregeerd — medianen zijn niet optelbaar. Gebieden met
          één wijk nemen het wijkcijfer over (dekking 1/1, wordt gemeld).
        </li>
        <li>
          <strong>GGW-totalen zijn benaderingen</strong>: elke wijk telt bij precies één gebied,
          terwijl de officiële catalogus minimaal één wijk kent (Noordelijke IJ-oevers-West) die in
          twee GGW-gebieden ligt. Voor formele gebiedscijfers is het BBGA van Onderzoek &amp;
          Statistiek Amsterdam de aangewezen bron.
        </li>
        <li>
          Aandelen (% 0–14, % 65+, % alleenwonend, % herkomst) zijn zelf berekend uit de absolute
          CBS-kolommen; inkomens (×€1.000 in de bron) zijn omgerekend naar euro&#39;s.
        </li>
        <li>
          <strong>Relatief</strong> = procentuele afwijking t.o.v. de gekozen referentie
          (Amsterdam of Oost-totaal). Bij percentages toont de tooltip ook de onderliggende waarde,
          omdat een relatieve afwijking bij kleine percentages snel groot oogt.
        </li>
      </ul>

      <h2>Duiding bij gebruik voor locatiekeuze</h2>
      <ul>
        <li>
          De thema&#39;s koppelen CBS-indicatoren aan Dynamo-diensten (jeugd- en jongerenwerk,
          ouderenwerk, maatschappelijke dienstverlening/schuldhulp, buurtwerk en ontmoeting,
          mantelzorgondersteuning, taal &amp; inburgering). Indicatoren zijn{' '}
          <em>proxies</em>: jeugdzorggebruik benadert jeugdproblematiek, verweduwing benadert
          eenzaamheidsrisico — het zijn signalen, geen vraagcijfers.
        </li>
        <li>
          Advies van het team: weeg <strong>absoluut volume</strong> (waar wonen de meeste mensen
          uit de doelgroep) én <strong>relatieve concentratie</strong> (waar wijkt de wijk het
          sterkst af). Een wijk met index 150 maar 200 ouderen is minder locatierelevant dan een
          wijk met index 110 en 2.000 ouderen.
        </li>
        <li>
          De kaartgeometrieën zijn gegeneraliseerde CBS-grenzen (via{' '}
          <BronLink state={state} id="pdok-wijkbuurt">PDOK</BronLink>) — bedoeld voor
          vergelijking, niet voor exacte grensbepaling.
        </li>
      </ul>

      <h2>Bron & techniek</h2>
      <ul>
        <li>
          Bron: <BronLink state={state} id="cbs-kwb">{ds.meta.source}</BronLink>; variabelendocumentatie:
          CBS Toelichting KWB 2025. Zie het tabblad{' '}
          <BronLink state={state}>Bronnen</BronLink> voor alle datasets met hun oorspronkelijke
          vindplaats en licentie.
        </li>
        <li>
          De tool is een zelfstandige React/TypeScript-applicatie (statisch te hosten). Nieuwe
          CBS-jaargangen verwerk je met <code>data-prep/build_data.py</code>; de app leest de
          gegenereerde <code>dashboard/public/data/index.json</code> (beschikbare gemeenten) en{' '}
          <code>dashboard/public/data/gm/&lt;GM&gt;.json</code> (per gemeente).
        </li>
        <li>Gegenereerd op {ds.meta.generated}.</li>
      </ul>
    </div>
  )
}
