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
    datum = "2026-09-17",
    titel = "Kaart: meerdere groepen optellen en een instelbare kleurschaal",
    punten = c(
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
