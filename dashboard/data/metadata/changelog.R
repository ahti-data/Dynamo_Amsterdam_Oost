#' Wat er in het dashboard veranderd is, voor de gebruikers ervan.
#'
#' Dit is geen technisch logboek -- daar is de git-historie voor. Hier staat wat
#' iemand die het dashboard gebruikt merkt: een nieuwe knop, een cijfer dat
#' anders uitvalt, een kaart die het eerst niet deed. In gewone taal, zonder
#' kolomnamen of functienamen.
#'
#' **Bij elke push naar main hoort hier een regel bij.** De app toont de
#' bovenste datum in de knop rechtsboven; een lezer ziet daaraan of er iets
#' nieuws is. Blijft dit bestand achter, dan denkt iedereen dat er niets
#' gebeurd is.
#'
#' Nieuwste bovenaan. `datum` in ISO-vorm (de knop maakt er zelf iets leesbaars
#' van), `titel` kort genoeg voor een kop, `punten` een of meer zinnen.

CHANGELOG <- list(
  list(
    datum = "2026-09-19",
    titel = "Nieuwe levering: meer uitsplitsingen, exacte noemers, gemiddelde score",
    punten = c(
      paste("Het dashboard draait op de nieuwe CBS-levering. Die heeft flink meer",
            "uitsplitsingen, en -- nieuw -- je kunt er naar meer dan een tegelijk",
            "uitsplitsen. \"Splits uit naar\" en \"Splits de lijn uit naar\" zijn daarom",
            "meerkeuzelijsten geworden: niets kiezen betekent niet uitsplitsen, en kies je er",
            "twee, dan krijg je de gekruiste groepen (bijvoorbeeld ondersteuningscombinatie",
            "x geslacht). Niet elke kruising zit in de levering; kies je er een die er niet",
            "is, dan zegt het dashboard dat, in plaats van je een lege grafiek te laten zien."),
      paste("De percentages kloppen nu preciezer. De levering geeft voortaan zelf hoeveel",
            "huishoudens of ouderen er in een groep zitten; dat hoefde het dashboard eerst",
            "terug te rekenen door de categorieen op te tellen, en dat viel te laag uit zodra",
            "er een categorie onderdrukt was -- waardoor het percentage te hoog uitkwam. Die",
            "noemer is nu het gepubliceerde aantal. Cijfers kunnen daardoor iets anders",
            "uitvallen dan voorheen; dat is een correctie, geen nieuwe meting."),
      paste("\"Aantal vormen ondersteuning\" is op veel meer wijken en buurten te zien. De",
            "omvang van een groep hangt niet van de gekozen risicoscore af, dus er is nu aan",
            "een enkele gepubliceerde rij genoeg waar er eerst een complete reeks nodig was.",
            "Dat was precies wat die indicator onder gebiedsniveau vrijwel leeg liet."),
      paste("Er is een nieuwe metric: gemiddelde score. Dat is een gemiddelde en geen aantal,",
            "dus daar geldt de keuze bij \"Weergave\" niet -- er staat altijd het gemiddelde",
            "zelf, met decimalen. Optellen kan er ook niet: kies je meerdere waarden of",
            "niveaus tegelijk, dan blijft de kaart leeg met de reden erbij, in plaats van dat",
            "er twee gemiddelden bij elkaar worden opgeteld."),
      paste("Onder de venn is de kolom n nu de omvang van de hele groep, inclusief de",
            "huishoudens of ouderen die in geen enkele kolom vallen. Een rij telt daar dus",
            "niet naartoe op -- dat stond er eerder anders, en staat er nu bij."),
      paste("In de legenda van de gedownloade kaart (png) ontbrak het procentteken als je een",
            "aandeel toonde, en stond \"Aantal\" boven de schaal. Dat klopt nu."),
      paste("De totale risicostapeling staat nu in twee keuzes. \"Totale risicostapeling\" is",
            "het gemiddelde aantal risicofactoren; \"Totale risicostapeling in klassen\" zijn de",
            "groepen 0, 1, 2 en 3 of meer, zoals je die eerder onder de eerste naam vond. Nieuw",
            "is ook \"Alle huishoudens met kinderen\" respectievelijk \"Alle ouderen (65+)\":",
            "de hele populatie zonder risicovoorwaarde."),
      paste("De klasse \"3 of meer risicofactoren\" kwam bij huishoudens met kinderen zonder",
            "naam uit de levering -- de aantallen waren er wel. Het dashboard zet die naam",
            "terug, dus de vierde klasse is weer gewoon te kiezen en te lezen."),
      paste("Op buurt- en wijkniveau bevat deze levering alleen Oost (63 buurten, 15 wijken).",
            "De rest van de stad blijft daar leeg, en dat staat nu boven de kaart en bij de",
            "regiokeuze. Belangrijk verschil: leeg betekent hier niet \"te weinig",
            "waarnemingen\", maar \"niet aangeleverd\". Vanaf gebiedsniveau zit de hele stad",
            "er gewoon in."),
      paste("De keuzelijst \"Metric\" laat nu alleen zien wat bij de gekozen indicator hoort.",
            "Niet elke indicator heeft elke metric -- de gemiddelde score bestaat alleen bij",
            "de totale risicostapeling -- en daardoor opende het dashboard op een lege kaart."),
      paste("Een percentage kan niet meer boven de 100% uitkomen. Bij hele kleine groepen",
            "konden teller en noemer net verschillend afgerond zijn, en dan stond er",
            "bijvoorbeeld 200% van een groep van tien. Het aantal zelf verandert niet."),
      paste("De titel boven de grafiek op Per regio noemde de waarde van de indicator in",
            "codevorm (\"0\") in plaats van met haar naam (\"Geen ondersteuning\"), anders dan",
            "de keuzelijst eronder en anders dan de Kaart-tab. Dat is nu gelijkgetrokken.")
    )
  ),
  list(
    datum = "2026-09-18",
    titel = "Think-cell-tabellen staan nu in Export history",
    punten = c(
      paste("\"Download data (think-cell)\" kwam niet in het tabblad Export history terecht --",
            "alleen \"Download slide\" deed dat. Daardoor was dat de enige export die je niet",
            "kon terugzoeken vanaf het bestand zelf."),
      paste("Nu levert elke think-cell-download een regel op, met hetzelfde korte download-id",
            "in de hoekcel van de werkmap. Zie je zo'n tabel ergens in een deck terug, dan vind",
            "je daarmee precies welke selectie en welk moment erachter zat -- en je kunt hem",
            "opnieuw downloaden of tegen de data van vandaag opnieuw laten bouwen."),
      "De ruwe xlsx-download blijft ongelogd: die draagt geen herkomstregel."
    )
  ),
  list(
    datum = "2026-09-17",
    titel = "Kaart: twee soorten aandeel, groepen optellen, instelbare kleurschaal",
    punten = c(
      paste("Bij \"Weergave\" kun je nu kiezen tegen welke noemer een aandeel afgezet",
            "wordt. \"Van regiototaal\" is ten opzichte van alle huishoudens of ouderen in",
            "die buurt, wijk, dat gebied of dat stadsdeel -- \"x% van alle gezinnen hier\".",
            "\"Binnen groep\" is ten opzichte van de gekozen groep zelf -- \"van de gezinnen",
            "met dit ondersteuningsbeeld heeft x% deze risicoscore\". Dat scheelt flink:",
            "dezelfde selectie is in Zuidoost 16,0% binnen de groep en 1,6% van het",
            "regiototaal. Welke van de twee je ziet staat in de titel en bij de legenda,",
            "en beide noemers staan in de xlsx."),
      paste("Is in een regio een van de opgetelde groepen onderdrukt, dan telt die regio",
            "op wat er wel gepubliceerd is. Dat cijfer is een ondergrens, en dat staat er",
            "ook bij: een gestippelde rand om de regio, boven de kaart hoeveel regio's het",
            "betreft, en in de tooltip hoeveel van de gekozen onderdelen er zijn --",
            "\"1 van de 3\" is iets heel anders dan \"5 van de 6\". In de xlsx staan de",
            "kolommen alle_groepen_aanwezig en onderdelen_gevonden. Zonder dit bleven",
            "sommige kaarten helemaal leeg."),
      paste("Dit geldt alleen voor groepen die je zelf optelt. De afgeleide indicatoren",
            "(ondersteuningssignaal, aantal vormen) vallen nog steeds helemaal weg als ze",
            "onvolledig zijn -- daar bepaalt de optelling de noemer van een percentage, en",
            "dat zou anders te hoog uitvallen."),
      paste("Bij \"Waarde van de indicator\" en \"Toon welk niveau\" zijn nu meerdere",
            "keuzes tegelijk mogelijk. Die worden opgeteld, inclusief de noemer, dus",
            "je kunt bijvoorbeeld Jeugdhulp, Psychosociale zorg en de combinatie",
            "daarvan als een groep op de kaart zetten."),
      paste("Valt een van de gekozen groepen in een regio onder de CBS-drempel, dan",
            "blijft die regio grijs. De optelling zou daar anders te laag uitvallen."),
      paste("De kleurschaal loopt door in plaats van in klassen, zodat het verschil",
            "tussen twee regio's in hetzelfde \"vakje\" zichtbaar blijft."),
      paste("Het bereik van die schaal is zelf in te stellen (\"Kleurschaal volgt de",
            "data\" uitzetten). Handig om twee kaarten naast elkaar te leggen: ze",
            "kleuren dan op dezelfde schaal. Regio's buiten het bereik krijgen de",
            "rand van de schaal, niet grijs."),
      "Deze knop is nieuw: hier staat voortaan wat er veranderd is."
    )
  ),
  list(
    datum = "2026-09-16",
    titel = "Kaart van een stadsdeel, heel Amsterdam, venn zonder risicoscore",
    punten = c(
      paste("De kaart is te begrenzen tot een stadsdeel (\"Toon\"), zodat je een kaart",
            "van alleen Oost kunt uitlichten, en is als png te downloaden."),
      paste("\"Heel Amsterdam\" staat nu bij de regio's op het tabblad Per regio, en is",
            "daar de standaardkeuze."),
      paste("De venn heeft een eigen indicatorkeuze en staat standaard op \"(alle)\":",
            "dan toont hij de ondersteuningsverdeling zelf, zonder dat je een",
            "risicoscore hoeft te kiezen."),
      paste("Onder de venn staat een tabel met de acht ondersteuningsgroepen tegen de",
            "losse risicofactoren R1 t/m R9."),
      paste("Let op: armoede (R1) loopt tot 2023 en betalingsachterstand",
            "zorgverzekering (R9) tot 2022. Een lege kolom is daar dus geen",
            "onderdrukking maar een bronregister dat niet doorloopt."),
      "Westpoort staat niet meer op de kaart: haven- en bedrijventerrein, nauwelijks huishoudens."
    )
  ),
  list(
    datum = "2026-09-15",
    titel = "Ondersteuningssignaal en aantal vormen als eigen indicator",
    punten = c(
      paste("Nieuw op de kaart: het percentage gezinnen dat een vorm van ondersteuning",
            "gebruikt (Amsterdam 2024: 42,9%), en hoeveel vormen tegelijk."),
      paste("Dezelfde uitsplitsingen zijn ook te kruisen met een risicoscore, om te",
            "zien hoe de risicostapeling per ondersteuningsgroep verschilt."),
      paste("Het vennfiguur is er ook als tabel bij gekomen: de acht deelgebieden",
            "tegen de categorieen van de gekozen risicoscore.")
    )
  )
)
