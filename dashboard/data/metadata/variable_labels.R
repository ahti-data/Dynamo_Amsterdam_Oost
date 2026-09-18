#' Nederlandse omschrijvingen voor de indicatoren en ondersteuningsgroepen in
#' de Dynamo-output (OT_HHKIND, OT_OUD).
#'
#' Overgenomen uit de outputverantwoording `Outcomes.xlsx` (tabbladen
#' "Definities-MPG" en "Definities-Ouderen"), niet verzonnen of afgeleid uit
#' de kolomnamen. Bij een nieuwe RA-levering met gewijzigde/nieuwe
#' variabelen: dit bestand bijwerken vanuit de nieuwe Outcomes.xlsx, niet de
#' kolomnaam zelf laten spreken.
#'
#' Alle `R_`-variabelen zijn risicoscores ("Axes: Risico" in Outcomes.xlsx):
#' variable_value 1 betekent dat dit risico aanwezig is bij het huishouden/de
#' oudere. `R_MPG_totaal`/`R_OUD_totaal` zijn de cumulatieve score (hoeveel
#' van de losse risico's tegelijk spelen).
#'
#' Levering `output_1b` splitst die cumulatieve score in tweeen, en dat is het
#' enige dat aan deze namen veranderde:
#'   - `R_MPG_totaal`/`R_OUD_totaal` draagt alleen nog het *gemiddelde* aantal
#'     risicofactoren (metric `average_score`, variable_value "nvt");
#'   - `R_MPG_totaal_cat`/`R_OUD_totaal_cat` draagt de klassen 0/1/2/3plus --
#'     wat tot `output_1a` onder `R_MPG_totaal`/`R_OUD_totaal` zelf stond;
#'   - `R_MPG_all`/`R_OUD_all` is de hele populatie in een enkele categorie
#'     (variable_value 1), zonder risicovoorwaarde.
#' Die drie zijn geen losse risicofactoren; RISICO_TOTAAL_* hieronder houdt ze
#' uit de risicofactor-tabel onder de venn.
#'
#' De O_MPG*/O_OUD*-ondersteuningsgroepen zijn elk een OF over 2-3
#' onderliggende ondersteuningsvormen (zie de pipeline,
#' `output_src/.../R/02_enrich_and_score.R`, `scoring_cols` -- elke groep is
#' "1 als om het even welke onderliggende vorm gebruikt wordt", geen keuze
#' tussen ze). `O_MPG_combination`/`O_OUD_combination` telt vervolgens welke
#' groepen tegelijk spelen per huishouden/oudere: "none" (geen van de 3),
#' "O_MPG1", ..., tot en met "O_MPG1 + O_MPG2 + O_MPG3" (alle 3).

#' variable_name -> omschrijving, voor huishoudens met kinderen (OT_HHKIND).
RISICO_LABELS_HHKIND <- c(
  R_MPG_totaal                    = "Totale risicostapeling (aantal risicofactoren R1–R9)",
  R_MPG_totaal_cat                = "Totale risicostapeling in klassen (0, 1, 2, 3 of meer risicofactoren R1–R9)",
  R_MPG_all                       = "Alle huishoudens met kinderen (geen risicovoorwaarde)",
  R_MPG1_armoede_hh                = "Armoede (huishoudinkomen < 130% sociaal minimum)",
  R_MPG2_laagopl_hh                = "Laag opleidingsniveau (ouder(s) zonder startkwalificatie)",
  R_MPG3_nieuwenederlander_hh      = "Nieuwe Nederlander (< 5 jaar in Nederland)",
  R_MPG4_eenoudergezin             = "Eenoudergezin",
  R_MPG5_werkloosheid_hh           = "Werkloosheid (≥ 1 jaar geen inkomen uit werk)",
  R_MPG6_kind_met_jonge_moeder_hh  = "Moeder < 20 jaar bij geboorte kind",
  R_MPG7_kind_met_jonge_vader_hh   = "Vader < 20 jaar (of onbekend) bij geboorte kind",
  R_MPG8_veranderingen_hh          = "Wijziging huishoudtype (scheiding of overlijden)",
  R_MPG9_wanbet_zv_hh              = "Betalingsachterstand zorgverzekering"
)

#' variable_name -> omschrijving, voor ouderen (OT_OUD).
RISICO_LABELS_OUD <- c(
  R_OUD_totaal                = "Totale risicostapeling (aantal risicofactoren R1–R5)",
  R_OUD_totaal_cat            = "Totale risicostapeling in klassen (0, 1, 2, 3 of meer risicofactoren R1–R5)",
  R_OUD_all                   = "Alle ouderen (65+) (geen risicovoorwaarde)",
  R_OUD1_armoede               = "Armoede (inkomen < 130% sociaal minimum)",
  R_OUD2_migratieachtergrond   = "Migratieachtergrond",
  R_OUD3_hhwijziging           = "Verweduwd/gescheiden (wijziging burgerlijke staat, afgelopen 3 jaar)",
  R_OUD4_alleenwonend          = "Alleenwonend",
  R_OUD5_geenkind              = "Geen levende/nabije kinderen"
)

#' De samenvattende R_-variabelen: de cumulatieve score (gemiddelde en klassen)
#' en de populatie zelf. Ze horen wel in de keuzelijst "Risicoscore" -- je wilt
#' de stapeling op de kaart kunnen zetten -- maar niet in de risicofactor-tabel
#' onder de venn: die zet per deelgebied af welk aandeel *een losse* factor
#' heeft, en `R_MPG_all` zou daar een kolom van 100% worden.
RISICO_TOTAAL_HHKIND <- c("R_MPG_totaal", "R_MPG_totaal_cat", "R_MPG_all")
RISICO_TOTAAL_OUD    <- c("R_OUD_totaal", "R_OUD_totaal_cat", "R_OUD_all")

#' O_MPG1/2/3 -> korte naam. Voor compacte weergave: dropdown-opties,
#' lijngrafiek-legenda, labels op de venn-cirkels.
ONDERSTEUNING_GROEP_LABELS_HHKIND <- c(
  O_MPG1 = "Jeugdhulp",
  O_MPG2 = "Psychosociale zorg (volwassenen)",
  O_MPG3 = "Sociaaleconomische ondersteuning"
)

#' O_MPG1/2/3 -> volledige omschrijving inclusief onderliggende signalen, voor
#' de toelichting bij de venn-figuur.
ONDERSTEUNING_GROEP_UITLEG_HHKIND <- c(
  O_MPG1 = "Jeugdhulp: ambulante jeugdhulp, jeugdhulp met verblijf, of jeugdbescherming.",
  O_MPG2 = "Psychosociale zorg (volwassenen): specialistische GGZ, Wmo, of verslavingsmedicatie.",
  O_MPG3 = "Sociaaleconomische ondersteuning: bijstand/WW/AO, WSNP, of ziektewet."
)

#' O_OUD1/2/3 -> korte naam.
ONDERSTEUNING_GROEP_LABELS_OUD <- c(
  O_OUD1 = "Ouderenzorg",
  O_OUD2 = "Psychosociale zorg",
  O_OUD3 = "Sociaaleconomische ondersteuning"
)

#' O_OUD1/2/3 -> volledige omschrijving inclusief onderliggende signalen.
ONDERSTEUNING_GROEP_UITLEG_OUD <- c(
  O_OUD1 = "Ouderenzorg: Wlz, Wmo, of wijkverpleging (Zvw).",
  O_OUD2 = "Psychosociale zorg: GGZ-gebruik, of psychofarmaca.",
  O_OUD3 = "Sociaaleconomische ondersteuning: bijzondere bijstand, of WSNP."
)

# ---------------------------------------------------------------------------
# Afgeleide ondersteuningsvariabelen
# ---------------------------------------------------------------------------
#
# Niet uit Outcomes.xlsx: deze staan niet als kolom in de levering maar worden
# in de prep-stap uit `O_MPG_combination`/`O_OUD_combination` afgeleid (zie
# data-prep/derive_support_splits.R). De omschrijvingen hieronder beschrijven
# dus wat de afleiding doet, niet een variabele uit het outputformulier.

#' Als indicator (`variable_name`): de ondersteuning zit in `variable_value`,
#' dus de noemer is de hele populatie en "Aandeel (%)" leest als *het
#' percentage huishoudens/ouderen dat ondersteuning gebruikt*.
ONDERSTEUNING_INDICATOR_LABELS <- c(
  O_MPG_ondersteuning = "Ondersteuningssignaal (wel/geen)",
  O_MPG_aantal_vormen = "Aantal vormen ondersteuning (0-3)",
  O_MPG_combinatie    = "Ondersteuningscombinatie (welke groepen)",
  O_OUD_ondersteuning = "Ondersteuningssignaal (wel/geen)",
  O_OUD_aantal_vormen = "Aantal vormen ondersteuning (0-3)",
  O_OUD_combinatie    = "Ondersteuningscombinatie (welke groepen)"
)

#' Als splitsvariabele (`split_var`): `variable_value` blijft de risicoscore,
#' dus dit kruist de ondersteuning met de risicostapeling.
ONDERSTEUNING_SPLIT_LABELS <- c(
  ondersteuningssignaal       = "wel/geen ondersteuningssignaal",
  aantal_ondersteuningsvormen = "aantal vormen ondersteuning"
)

#' De categorieen van beide afgeleide variabelen, in beide vormen: als
#' `variable_value` van de indicator en als `split_level` van de splitsing zijn
#' het dezelfde codes.
ONDERSTEUNING_NIVEAU_LABELS <- c(
  onbekend = "Niet toe te wijzen (onderdrukt)",
  geen = "Geen ondersteuningssignaal",
  wel  = "Wel een ondersteuningssignaal",
  "0"  = "Geen ondersteuning",
  "1"  = "1 vorm ondersteuning",
  "2"  = "2 vormen ondersteuning",
  "3"  = "Alle 3 de vormen"
)
