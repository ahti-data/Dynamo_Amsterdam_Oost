#' Wat een metric telt, en wat je er dus mee mag doen.
#'
#' Het lange schema zet elke metric in dezelfde kolom (`metric_value`), maar ze
#' zijn niet van hetzelfde soort, en dat bepaalt of optellen en delen mag:
#'
#'   - `n_households` / `n_ouderen_with_var_value` tellen de populatie-eenheid
#'     zelf. Optelbaar, en hun noemer is het aantal huishoudens/ouderen -- dus
#'     precies wat `n_split` (en op de totaalrij `n_totaal`) exact geeft.
#'   - de `n_kinderen_*`-metrics tellen kinderen tegen een huishoudnoemer. Ook
#'     optelbaar, maar `n_totaal`/`n_split` is er *niet* de noemer van: die telt
#'     huishoudens (PLAN.md 2b). Hun noemer blijft de som over de
#'     variable_value-categorieen binnen dezelfde slice.
#'   - `average_score` is een gemiddelde. Niet optelbaar (de som van twee
#'     gemiddelden is geen gemiddelde) en niet deelbaar (een aandeel van een
#'     gemiddelde bestaat niet). Het dashboard toont hem daarom altijd absoluut
#'     en weigert hem op te tellen; zie map_aggregate() in utils/map.R.
#'
#' Nieuwe metrics vallen vanzelf in de middelste categorie: optelbaar, met de
#' categoriesom als noemer. Dat is de veilige aanname -- een nieuw gemiddelde
#' wordt hieronder herkend aan zijn naam, en een nieuwe populatietelling hoort
#' expliciet in METRIC_POPULATIE_EENHEID te worden gezet.

# De metrics die de populatie-eenheid zelf tellen, per levering geverifieerd.
METRIC_POPULATIE_EENHEID <- c("n_households", "n_ouderen_with_var_value")

# Gemiddelden. `average_score` is de metric uit levering output_1b; het patroon
# vangt ook een volgende (`average_*`, `mean_*`, `gemiddelde_*`), zodat een
# nieuw gemiddelde niet stilzwijgend als telling behandeld wordt -- dat zou het
# laten optellen, en dan staat er een getal op de kaart dat nergens op slaat.
METRIC_GEMIDDELDE_PATROON <- "^(average|mean|gemiddelde)([_.]|$)"

#' Is deze metric een gemiddelde? Gevectoriseerd.
metric_is_gemiddelde <- function(x) {
  !is.na(x) & grepl(METRIC_GEMIDDELDE_PATROON, as.character(x))
}

#' Telt deze metric de populatie-eenheid zelf (huishoudens/ouderen)?
#' Gevectoriseerd. Bepaalt of `n_split`/`n_totaal` de juiste noemer is.
metric_telt_populatie <- function(x) {
  !is.na(x) & as.character(x) %in% METRIC_POPULATIE_EENHEID
}

#' Mag deze metric over cellen opgeteld worden?
metric_is_optelbaar <- function(x) !metric_is_gemiddelde(x)
