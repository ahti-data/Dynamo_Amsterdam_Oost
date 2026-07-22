########################################################################
# CBS Microdata — analysepijplijn ahti-project 9097
# "Zorgsystemen: gebruik over de regelingen heen"
#
# Implementeert het analyseplan uit `cbs plan.md` (§5 en §6), volgens de
# scriptstructuur uit §7: inlezen -> populatie & koppeling -> analyse
# -> gentrificatie-analyse per doelgroep -> output-aggregatie met
# disclosure-controle.
#
# Dit script draait UITSLUITEND binnen de beveiligde CBS-omgeving (BMO).
# Padnamen hieronder zijn placeholders (§0) — aanpassen aan de daadwerkelijke
# mapstructuur die ahti in de BMO heeft. Er verlaat geen data de omgeving
# via dit script buiten wat expliciet via schrijf_output() wegschrijft (§11),
# en die functie past de disclosure-regels uit plan §8 toe.
########################################################################


# ============================================================
# 0. Instellingen
# ============================================================

library(haven)        # inlezen .sav/.sas7bdat
library(data.table)   # joins, groeperen, panelopbouw (zie plan §6)
library(cluster)      # k-means / PAM voor typologieën
library(mclust)        # latent class / model-based clustering
library(lme4)          # multilevel modellen
library(survival)      # sterfte-analyse (Cox / Kaplan-Meier)
library(msm)           # meerstaps-transitiemodellen
library(broom)
library(broom.mixed)
library(ggplot2)

# --- Padnamen: AANPASSEN aan de BMO-mapstructuur van ahti --------------
STAPMON_PAD     <- "G:/Stapelingsmonitor"      # map met Stapelingsmonitor-thema's per jaar
REGELING_PAD    <- "G:/Bestanden/9097"         # map met de losse regelingenbestanden (plan §3.1)
GENTRIFICATIE_PAD <- "G:/Bestanden/9096"       # vastgoed-/verhuisbestanden (plan §3.2) — LET OP:
                                                # ander project dan 9097, zie plan §9 stap 0b
OUTPUT_PAD    <- "G:/Output/cbs_plan"          # enige map die dit script naar wegschrijft

dir.create(OUTPUT_PAD, showWarnings = FALSE, recursive = TRUE)

# --- Onderzoeksperiode en scope -----------------------------------------
JAREN <- 2017:2023   # vanaf 2017: de meeste STAPMON-thema's (Werk, Uitkeringen-detail,
                      # Gezondheid & Medicijngebruik, Jeugd-detail, Wonen, Rechtsbescherming)
                      # zijn pas vanaf verslagjaar 2017 beschikbaar (plan §3.0)

# 15 CBS-wijken van stadsdeel Amsterdam Oost (WK0363M*), zie de bestaande
# Dynamo Oost Monitor voor de herkomst van deze codelijst.
OOST_WIJKCODES <- c(
  "036300", "036301", "036302", "036303", "036304",
  "036305", "036306", "036307", "036308", "036309",
  "036310", "036311", "036312", "036313", "036314"
)  # PLACEHOLDER: vervangen door de exacte 2-cijferige WC-waarden (thema
   # Achtergrondkenmerken gebruikt GEM+WC apart, niet de volledige GWB-code
   # in 1 veld) — controleren tegen de CBS-buurtcodelijst in de BMO
   # (\\8_Utilities\\Code_Listings\\Wijkbuurtcodes\\, zie plan §3.0)

AMSTERDAM_GEMCODE <- "0363"

set.seed(20260712)  # vast seed voor reproduceerbare clustering (§5.3)


# ============================================================
# 1. Inlezen — Stapelingsmonitor themabestanden (plan §3.0)
# ============================================================
# Elk thema wordt in zijn geheel geleverd (geen losse variabelen), en de
# bestandsnaam-conventie is "Stapelingsmonitor <jaar> - <Thema>.sav"
# (zie CBS-documentatierapport, hoofdstuk 2).

lees_stapmon_thema <- function(thema, jaren = JAREN, kolommen = NULL) {
  # thema: exacte thema-naam zoals in de bestandsnaam, bv. "Achtergrondkenmerken"
  bestanden <- file.path(STAPMON_PAD, sprintf("Stapelingsmonitor %d - %s.sav", jaren, thema))
  bestaand  <- bestanden[file.exists(bestanden)]
  ontbrekend <- jaren[!file.exists(bestanden)]
  if (length(ontbrekend) > 0) {
    message(sprintf("Thema '%s': geen bestand voor jaren %s (nog niet aangevraagd/beschikbaar?)",
                     thema, paste(ontbrekend, collapse = ", ")))
  }
  panelen <- lapply(seq_along(bestaand), function(i) {
    jaar <- as.integer(sub(".*Stapelingsmonitor (\\d{4}).*", "\\1", bestaand[i]))
    dt <- as.data.table(read_sav(bestaand[i], col_select = kolommen))
    dt[, JAAR := jaar]
    dt
  })
  rbindlist(panelen, use.names = TRUE, fill = TRUE)
}

# --- Achtergrondkenmerken: basis, geografie, huishoudsleutels ------------
achtergrond <- lees_stapmon_thema(
  "Achtergrondkenmerken",
  kolommen = c("RINPERSOONS", "RINPERSOON", "GESLACHT", "LEEFTIJD",
               "HERKOMST", "HERKOMSTLAND", "BURGSTAAT", "TYPEHH",
               "AANTKINDHH", "AANTVOLWHH", "AANT65PLUSHH", "AANTPPHH",
               "GEM", "WC", "BC",
               "HUISHOUDNR", "DATUMAANVANGHH",
               "RINPERSOONSKERN", "RINPERSOONKERN")
)

# --- Inkomen: armoede-indicatoren (plan §5, punt 1) ----------------------
inkomen <- lees_stapmon_thema(
  "Inkomen",
  kolommen = c("RINPERSOONS", "RINPERSOON",
               "INKHHGEST", "ARMOEDE", "LANGARMOEDE",
               "BELANGINKBRONPERS")
)

# --- Vermogen en schulden: smalle schulddefinitie ------------------------
vermogen <- lees_stapmon_thema(
  "Vermogen en schulden",
  kolommen = c("RINPERSOONS", "RINPERSOON",
               "SMALLE_SCHULD", "SMALLE_SCHULD_HUISHOUDEN", "WSNP")
)

# --- Uitkeringen ----------------------------------------------------------
uitkeringen <- lees_stapmon_thema(
  "Uitkeringen",
  kolommen = c("RINPERSOONS", "RINPERSOON",
               "WW", "AO", "BIJSTAND", "BIJSTAND_PWET", "ZIEKTEWET",
               "HOPPER", "BIJSTANDSDUUR")
)

# --- Wmo -------------------------------------------------------------------
wmo <- lees_stapmon_thema("Wmo")  # kolomnamen niet exact gedocumenteerd in het
                                  # rapport; alle variabelen van dit thema
                                  # ophalen en in stap 4 selecteren

# --- Wlz --------------------------------------------------------------------
wlz <- lees_stapmon_thema(
  "Wlz",
  kolommen = c("RINPERSOONS", "RINPERSOON",
               "WLZ_INDICATI", "WLZ_VERBLIJF", "WLZ_VPT", "WLZ_MPT", "WLZ_PGB")
)

# --- Jeugd -------------------------------------------------------------------
jeugd <- lees_stapmon_thema("Jeugd")  # bevat o.a. JHz*/JBots/JBvoogdij/JR en
                                      # JURIDISCHE_OUDER_KIND_JEUGDZORG (plan §4)

# --- Gezondheid & Welzijn (GGZ, zorgkosten, LVB) -----------------------------
gezondheid_welzijn <- lees_stapmon_thema(
  "Gezondheid & Welzijn",
  kolommen = c("RINPERSOONS", "RINPERSOON",
               "GGZ", "LVB", "SOMZORGKOSTEN_INCLGGZ", "SOMZORGKOSTEN_EXCLGGZ")
)

# --- Gezondheid & Medicijngebruik --------------------------------------------
medicijn <- lees_stapmon_thema(
  "Gezondheid & Medicijngebruik",
  kolommen = c("RINPERSOONS", "RINPERSOON",
               "MEDICIJN_PSYCHOFARMACA", "MEDICIJN_ANTIDEPRESSIVA",
               "MEDICIJN_ANTIPSYCHOTICA", "MEDICIJN_VERSLAVING")
)

# --- Rechtsbescherming en veiligheid (optionele extra dimensie, plan §5.2) --
veiligheid <- lees_stapmon_thema(
  "Rechtsbescherming en veiligheid",
  kolommen = c("RINPERSOONS", "RINPERSOON", "VERDACHTE_MISDRIJF", "GEDETINEERD")
)


# ============================================================
# 2. Inlezen — aanvullende losse regelingenbestanden (plan §3.1)
# ============================================================
# Alleen nodig voor verdieping (klinische/justitiële detail) die STAPMON
# niet biedt, en voor overlijden/doodsoorzaak (niet in STAPMON).

lees_sav <- function(pad, kolommen = NULL) as.data.table(read_sav(pad, col_select = kolommen))

overlijden <- lees_sav(
  file.path(REGELING_PAD, "GBAOVERLIJDENTAB.sav"),
  kolommen = c("RINPERSOONS", "RINPERSOON", "DATUMOVERLIJDEN")
)
doodsoorzaak <- lees_sav(
  file.path(REGELING_PAD, "DOODOORZTAB.sav"),
  kolommen = c("RINPERSOONS", "RINPERSOON", "DOODOORZ_HOOFDGROEP")
)

# GGZ-hoofddiagnose-detail (verdieping op de GGZ-vlag uit gezondheid_welzijn)
ggz_hoofddiag <- lees_sav(
  file.path(REGELING_PAD, "GGZDBCTRAJECTENHOOFDDIAGTAB.sav")
)


# ============================================================
# 3. Populatieafbakening en koppeling (plan §4)
# ============================================================

# --- 3.1 Basispopulatie: Amsterdam Oost, geldige persoonssleutel ------------
# RINPERSOONS == "R": geldig BSN teruggevonden in de BRP (plan §4) — alleen
# deze records zijn geschikt om te koppelen/aggregeren op persoonsniveau.
populatie_oost <- achtergrond[
  RINPERSOONS == "R" & GEM == AMSTERDAM_GEMCODE & WC %in% OOST_WIJKCODES
]

cat(sprintf("Basispopulatie Amsterdam Oost: %d persoon-jaarrecords, %d unieke personen\n",
            nrow(populatie_oost), uniqueN(populatie_oost, by = c("RINPERSOONS", "RINPERSOON"))))

# --- 3.2 Persoon-jaar-panel opbouwen: left join vanuit de populatie ---------
# Belangrijk (plan §4): join vanuit de populatie, niet vanuit de
# regelingenbestanden, anders vallen niet-gebruikers uit de teller.
# `merge(..., all.x = TRUE)` gebruikt i.p.v. data.table's `X[Y, on=]`-syntax:
# die laatste neemt Y (de i-tabel) als basis van het resultaat, dus
# `populatie_oost[inkomen, on=...]` zou juist de regelingenbestanden als
# basis nemen — precies het omgekeerde van wat hier nodig is.
sleutel <- c("RINPERSOONS", "RINPERSOON", "JAAR")

panel <- merge(populatie_oost, inkomen,             by = sleutel, all.x = TRUE)
panel <- merge(panel,          vermogen,            by = sleutel, all.x = TRUE)
panel <- merge(panel,          uitkeringen,         by = sleutel, all.x = TRUE)
panel <- merge(panel,          wmo,                 by = sleutel, all.x = TRUE)
panel <- merge(panel,          wlz,                 by = sleutel, all.x = TRUE)
panel <- merge(panel,          jeugd,               by = sleutel, all.x = TRUE)
panel <- merge(panel,          gezondheid_welzijn,  by = sleutel, all.x = TRUE)
panel <- merge(panel,          medicijn,            by = sleutel, all.x = TRUE)
panel <- merge(panel,          veiligheid,          by = sleutel, all.x = TRUE)

# --- 3.3 Huishoudkoppeling: LET OP twee verschillende sleutels (plan §4) ----
# BRP-huishouden (voor de meeste variabelen):
panel[, huishouden_brp := paste(HUISHOUDNR, DATUMAANVANGHH)]
# Inkomensstatistiek-huishouden (voor inkomen/vermogen):
panel[, huishouden_ink := paste(RINPERSOONSKERN, RINPERSOONKERN)]

# --- 3.4 Sterfte koppelen (voor analyse in §6) ------------------------------
panel <- overlijden[panel, on = c("RINPERSOONS", "RINPERSOON")]
panel <- doodsoorzaak[panel, on = c("RINPERSOONS", "RINPERSOON")]


# ============================================================
# 4. Cross-domein gebruiksindicatoren per persoon-jaar (plan §5, punt 1)
# ============================================================

# Jeugdhulp-vormvariabelen (JH*, plan §3.0 thema Jeugd) eerst apart optellen:
# .SD/.SDcols samen met andere := velden in één aanroep is instabiel gebleken
# (data.table crasht hierop), daarom in een eigen stap berekend.
jeugd_kolommen <- grep("^JH", names(panel), value = TRUE)
panel[, ind_jeugd := as.integer(rowSums(.SD, na.rm = TRUE) > 0), .SDcols = jeugd_kolommen]

panel[, `:=`(
  ind_bijstand = as.integer(BIJSTAND == 1 | BIJSTAND_PWET == 1),
  ind_ww       = as.integer(WW == 1),
  ind_ao       = as.integer(AO == 1),
  ind_wmo      = as.integer(!is.na(WMOBUS) & WMOBUS == 1),   # kolomnaam controleren (§1 opmerking)
  ind_wlz      = as.integer(WLZ_INDICATI == 1),
  ind_ggz      = as.integer(GGZ == 1),
  ind_medicijn_psych = as.integer(MEDICIJN_PSYCHOFARMACA == 1 | MEDICIJN_ANTIDEPRESSIVA == 1 |
                                    MEDICIJN_ANTIPSYCHOTICA == 1),
  ind_armoede  = as.integer(ARMOEDE == 1),
  ind_schuld   = as.integer(SMALLE_SCHULD == 1),
  ind_verdachte = as.integer(VERDACHTE_MISDRIJF == 1),
  ind_gedetineerd = as.integer(GEDETINEERD == 1)
)]


# ============================================================
# 5. Stapelingsindex (plan §5, punt 2)
# ============================================================

regeling_indicatoren <- c("ind_bijstand", "ind_ww", "ind_ao", "ind_wmo", "ind_wlz",
                          "ind_jeugd", "ind_ggz", "ind_medicijn_psych", "ind_armoede",
                          "ind_schuld", "ind_verdachte", "ind_gedetineerd")

panel[, stapelingsindex := rowSums(.SD, na.rm = TRUE), .SDcols = regeling_indicatoren]

# Kostengewogen variant (zorgkosten uit thema Gezondheid & Welzijn)
panel[, stapelingsindex_gewogen := stapelingsindex *
        (1 + pmin(SOMZORGKOSTEN_INCLGGZ / 10000, 2))]  # eenvoudige demping; te herzien

samenvatting_stapeling <- panel[, .(
  gem_stapeling   = mean(stapelingsindex, na.rm = TRUE),
  mediaan_stapeling = median(stapelingsindex, na.rm = TRUE),
  n = .N
), by = .(JAAR, WC)]


# ============================================================
# 6. Typologieën op persoons-/huishoudniveau (plan §5, punt 3)
# ============================================================
# Individueel analogon van de bestaande buurt-k-means-typologieën
# (`multivar_foundation.json` in de Dynamo-monitor), zonder ecologische
# aggregatie: hier op persoonsniveau, binnen één verslagjaar.

typologie_variabelen <- c("LEEFTIJD", "AANTPPHH", "INKHHGEST", "stapelingsindex")

cluster_data <- panel[JAAR == max(JAREN) & complete.cases(panel[, ..typologie_variabelen])]
cluster_matrix <- scale(cluster_data[, ..typologie_variabelen])

# Aantal clusters bepalen (indicatief, niet geoptimaliseerd)
K <- 4
kmeans_fit <- kmeans(cluster_matrix, centers = K, nstart = 25)
cluster_data[, typologie := factor(kmeans_fit$cluster)]

# Model-based alternatief (laat mclust zelf het aantal clusters kiezen)
mclust_fit <- Mclust(cluster_matrix)
cluster_data[, typologie_mclust := factor(mclust_fit$classification)]

typologie_profielen <- cluster_data[, lapply(.SD, mean, na.rm = TRUE),
                                     by = typologie, .SDcols = typologie_variabelen]
typologie_profielen[, n := cluster_data[, .N, by = typologie]$N]


# ============================================================
# 7. Multilevel modellen: persoon genest in buurt (plan §5, punt 4)
# ============================================================
# Toetst hoeveel van de buurtvariatie in de huidige monitor werkelijk
# individueel verklaarbaar is versus contextueel (buurt-random-effect).

model_data <- panel[JAAR == max(JAREN)]

multilevel_fit <- glmer(
  ind_wmo ~ LEEFTIJD + AANTPPHH + scale(INKHHGEST) + ind_armoede + (1 | WC),
  data = model_data,
  family = binomial
)

multilevel_samenvatting <- broom.mixed::tidy(multilevel_fit, effects = "fixed")
buurt_variantie <- as.data.frame(VarCorr(multilevel_fit))  # random-effect variantie per buurt


# ============================================================
# 8. Trajectanalyse / transitiematrices (plan §5, punt 5)
# ============================================================
# Vervangt de gebiedstrendextrapolatie (`forecast.ts`) door een
# cohort-gebaseerde aanpak op individueel niveau.

# Eenvoudige toestand per persoon-jaar (mutually exclusive, meest urgente eerst)
panel[, toestand := fifelse(ind_wlz == 1, "Wlz",
                     fifelse(ind_wmo == 1 & ind_ggz == 1, "Wmo+GGZ",
                     fifelse(ind_wmo == 1, "Wmo",
                     fifelse(ind_ggz == 1, "GGZ",
                     fifelse(ind_bijstand == 1, "Bijstand",
                     "Geen regeling")))))]

# Transitiematrix jaar t -> t+1 per persoon
panel_wide <- dcast(panel, RINPERSOONS + RINPERSOON ~ JAAR, value.var = "toestand")
transitie_paren <- lapply(seq_along(JAREN)[-length(JAREN)], function(i) {
  kolom_t  <- as.character(JAREN[i])
  kolom_t1 <- as.character(JAREN[i + 1])
  data.table(van = panel_wide[[kolom_t]], naar = panel_wide[[kolom_t1]])
})
transitietabel <- rbindlist(transitie_paren)[!is.na(van) & !is.na(naar)]
transitiematrix <- transitietabel[, .N, by = .(van, naar)][
  , prop := N / sum(N), by = van
]

# Alternatief: multistate-model met msm voor continue-tijd-transities
# (indien voldoende waarnemingen per overgang — zie disclosure-check §10)
# msm_fit <- msm(as.integer(factor(toestand)) ~ JAAR, subject = RINPERSOON,
#                data = panel, qmatrix = ...)  # qmatrix vooraf specificeren


# ============================================================
# 9. Sterfte als eindpunt (plan §5, punt 6)
# ============================================================

overleden_ooit <- panel[, .(overleden = any(!is.na(DATUMOVERLIJDEN))), by = .(RINPERSOONS, RINPERSOON)]
stapeling_voor_overlijden <- panel[overleden_ooit, on = c("RINPERSOONS", "RINPERSOON")][
  , .(max_stapeling = max(stapelingsindex, na.rm = TRUE)), by = .(RINPERSOONS, RINPERSOON, overleden)
]

sterfte_model <- glm(overleden ~ max_stapeling, data = stapeling_voor_overlijden, family = binomial)
sterfte_samenvatting <- broom::tidy(sterfte_model)

# Voor een survival-aanpak met tijd-tot-overlijden (indien datum beschikbaar):
# survival_data <- ...  # persoon-niveau met start/eind/event
# cox_fit <- coxph(Surv(tijd, event) ~ stapelingsindex, data = survival_data)


# ============================================================
# 10. Gentrificatie-analyse per Dynamo-doelgroep (plan §6)
# ============================================================
# Vastgoed-/verhuisbestanden komen uit ahti-project 9096, niet 9097
# (plan §3.2/§9 stap 0b) — apart ingelezen.

woz          <- lees_sav(file.path(GENTRIFICATIE_PAD, "BAGWOZTAB.sav"))
eigendom     <- lees_sav(file.path(GENTRIFICATIE_PAD, "EIGENDOMTAB.sav"))
verhuisgebeurtenissen <- lees_sav(
  file.path(GENTRIFICATIE_PAD, "GBAADRESGEBEURTENISBUS.sav"),
  kolommen = c("RINPERSOONS", "RINPERSOON", "DATUMAANVANGADRES",
               "VORIGE_WC", "VORIGE_BC", "NIEUWE_WC", "NIEUWE_BC")
)  # kolomnamen indicatief — exacte namen controleren in de CBS-documentatie
   # van GBAADRESGEBEURTENISBUS in de BMO

# --- 10.1 Gentrificatie-intensiteit per buurt-jaar (plan §6, voorspeller) ---
woz[, JAAR := as.integer(format(as.Date(PEILDATUM), "%Y"))]  # kolomnaam PEILDATUM indicatief
woz_per_buurt <- woz[, .(gem_woz = mean(WOZWAARDE, na.rm = TRUE), n_obj = .N), by = .(BC, JAAR)]
woz_per_buurt[order(BC, JAAR), woz_groei := gem_woz / shift(gem_woz) - 1, by = BC]

eigendom_per_buurt <- eigendom[, .(
  aandeel_sociale_huur = mean(EIGENDOMSVORM == "sociale_huur", na.rm = TRUE)  # waarde indicatief
), by = .(BC, JAAR)]
eigendom_per_buurt[order(BC, JAAR), verandering_soc_huur := aandeel_sociale_huur - shift(aandeel_sociale_huur), by = BC]

gentrificatie_intensiteit <- merge(woz_per_buurt, eigendom_per_buurt, by = c("BC", "JAAR"), all = TRUE)

# --- 10.2 Dynamo-doelgroepen definiëren (plan §6, tabel) --------------------
panel[, doelgroep := fifelse(LEEFTIJD < 15, "Kinderen (0-14)",
                      fifelse(LEEFTIJD < 25, "Jongeren (15-24)",
                      fifelse(LEEFTIJD < 45, "Overig (25-44)",
                      fifelse(LEEFTIJD < 65, "Aankomende senioren (45-64)",
                      "Ouderen (65+)"))))]
panel[, is_alleenwonend := as.integer(AANTPPHH == 1)]

# --- 10.3 Blijf/vertrek/instroom per doelgroep, buurt en jaar ---------------
# Koppel verhuisgebeurtenissen aan de populatie om per persoon-jaar te
# bepalen of iemand is gebleven, vertrokken (uit Oost) of ingestroomd (in Oost).
verhuis_oost <- verhuisgebeurtenissen[
  VORIGE_WC %in% OOST_WIJKCODES | NIEUWE_WC %in% OOST_WIJKCODES
]
verhuis_oost[, `:=`(
  JAAR = as.integer(format(as.Date(DATUMAANVANGADRES), "%Y")),
  status_verhuizing = fifelse(VORIGE_WC %in% OOST_WIJKCODES & !NIEUWE_WC %in% OOST_WIJKCODES, "vertrokken",
                       fifelse(!VORIGE_WC %in% OOST_WIJKCODES & NIEUWE_WC %in% OOST_WIJKCODES, "ingestroomd", "verhuisd_binnen_oost"))
)]

panel_met_status <- merge(panel, verhuis_oost[, .(RINPERSOONS, RINPERSOON, JAAR, status_verhuizing)],
                           by = c("RINPERSOONS", "RINPERSOON", "JAAR"), all.x = TRUE)
panel_met_status[is.na(status_verhuizing), status_verhuizing := "blijver"]

decompositie_per_doelgroep <- panel_met_status[, .(
  n                = .N,
  gem_inkomen      = mean(INKHHGEST, na.rm = TRUE),
  aandeel_armoede  = mean(ind_armoede, na.rm = TRUE),
  aandeel_jeugdhulp = mean(ind_jeugd, na.rm = TRUE),
  aandeel_wmo      = mean(ind_wmo, na.rm = TRUE)
), by = .(doelgroep, status_verhuizing, JAAR, WC)]

# --- 10.4 Interactiemodel: doelgroep x gentrificatie-intensiteit ------------
# Toetst rechtstreeks de hypothese: treedt het effect sterker/eerder op bij
# kinderen dan bij ouderen? (plan §6, punt 2)
model_data_gentrificatie <- merge(
  panel_met_status[JAAR == max(JAREN)],
  gentrificatie_intensiteit,
  by.x = c("WC", "JAAR"), by.y = c("BC", "JAAR"), all.x = TRUE
)

interactie_fit <- glmer(
  ind_jeugd ~ doelgroep * woz_groei + LEEFTIJD + scale(INKHHGEST) + (1 | WC),
  data = model_data_gentrificatie[doelgroep %in% c("Kinderen (0-14)", "Ouderen (65+)")],
  family = binomial
)
interactie_samenvatting <- broom.mixed::tidy(interactie_fit, effects = "fixed")

# --- 10.5 Kind-van-instromer vs. kind-van-blijver (plan §6, punt 3) ---------
# Via KINDOUDERTAB/JURIDISCHE_OUDER_KIND_JEUGDZORG bepalen of het kind bij
# een recent ingestroomd gezin hoort; hier via de ouder-status_verhuizing
# indien KINDOUDERTAB al gekoppeld is aan `panel` (zie plan §4) — anders
# eerst een aparte join met de losse kind-ouder-tabel (§3.1) toevoegen.
kinderen_naar_oudergezin <- panel_met_status[
  doelgroep == "Kinderen (0-14)",
  .(aandeel_jeugdhulp = mean(ind_jeugd, na.rm = TRUE), n = .N),
  by = .(gezin_status = status_verhuizing, JAAR, WC)
]  # `gezin_status` hier op basis van de status van het kind zelf; voor een
   # zuivere test moet dit de status van de OUDER zijn (plan §6, punt 3) —
   # aanpassen zodra de ouder-koppeling in de panelopbouw is toegevoegd.

# --- 10.6 Doelgroep-tijdlijn als eindproduct (plan §6, punt 4) --------------
doelgroep_tijdlijn <- panel_met_status[, .(
  n = .N,
  aandeel_blijver     = mean(status_verhuizing == "blijver"),
  aandeel_instromer   = mean(status_verhuizing == "ingestroomd"),
  aandeel_vertrokken  = mean(status_verhuizing == "vertrokken"),
  gem_stapeling       = mean(stapelingsindex, na.rm = TRUE)
), by = .(doelgroep, JAAR, WC)]


# ============================================================
# 11. Output-aggregatie en disclosure-controle (plan §8/§9)
# ============================================================
# ENIGE plek in dit script die output produceert die de BMO mag verlaten.
# Past de regels uit plan §8 toe: min. 10 eenheden algemeen, min. 100 voor
# inkomen/vermogen, geen dominante bijdrager >50% (kwantitatief) / >90%
# (frequentietabel-rij/kolom), geen individuele sleutels in de output.
# Let op bij de doelgroep-uitsplitsingen (§10): doelgroep x buurt x jaar
# maakt cellen sneller klein (plan §10, risico 11) — zo nodig hergroeperen
# naar wijkniveau vóór het wegschrijven.

MIN_N_ALGEMEEN <- 10
MIN_N_INKOMEN_VERMOGEN <- 100  # plan §7: strengere regel voor inkomen/vermogen

schrijf_output <- function(tabel, naam, telling_kolom = "n",
                            is_inkomen_vermogen = FALSE,
                            dominantie_kolom = NULL) {
  drempel <- if (is_inkomen_vermogen) MIN_N_INKOMEN_VERMOGEN else MIN_N_ALGEMEEN
  onveilig <- tabel[[telling_kolom]] < drempel
  if (any(onveilig)) {
    message(sprintf("'%s': %d van %d rijen onder de celgrootte-drempel (%d) — GEEN output, cellen onderdrukken of hergroeperen.",
                     naam, sum(onveilig), nrow(tabel), drempel))
    tabel <- tabel[!onveilig]
  }
  if (!is.null(dominantie_kolom)) {
    # Dominantiecontrole: grootste bijdrager mag niet >50% van een
    # kwantitatieve celtotaal zijn (plan §7) — hier indicatief, exacte
    # implementatie hangt af van de brondata per output.
    message("Dominantiecontrole handmatig verifiëren vóór indiening bij outputtoetsing.")
  }
  # Geen RINPERSOON(S) of andere individuele sleutels in de wegschrijf-tabel:
  stopifnot(!any(grepl("^RINPERSOON", names(tabel))))
  write.csv(tabel, file.path(OUTPUT_PAD, paste0(naam, ".csv")), row.names = FALSE)
  invisible(tabel)
}

# Voorbeeld-toepassingen — elk vóór indiening bij CBS-outputtoetsing (§7)
# nogmaals handmatig controleren, dit script is een hulpmiddel, geen
# vervanging van die toetsing.
schrijf_output(samenvatting_stapeling, "stapeling_per_wijk_jaar", telling_kolom = "n")
schrijf_output(typologie_profielen, "typologie_profielen", telling_kolom = "n")
schrijf_output(transitiematrix, "transitiematrix", telling_kolom = "N")
schrijf_output(as.data.table(multilevel_samenvatting), "multilevel_modeluitkomst")
schrijf_output(as.data.table(sterfte_samenvatting), "sterfte_modeluitkomst")

# Gentrificatie-analyse per doelgroep (§10) — vóór wegschrijven eerst op
# wijkniveau samenvatten als de buurt-uitsplitsing onder de drempel duikt
schrijf_output(decompositie_per_doelgroep, "gentrificatie_decompositie_per_doelgroep", telling_kolom = "n")
schrijf_output(as.data.table(interactie_samenvatting), "gentrificatie_interactiemodel_kinderen_ouderen")
schrijf_output(kinderen_naar_oudergezin, "jeugdhulp_naar_gezinsstatus", telling_kolom = "n")
schrijf_output(doelgroep_tijdlijn, "doelgroep_tijdlijn_gentrificatie", telling_kolom = "n")

# Geaggregeerde visualisatie (plan §6: nooit een scatter van individuele
# punten; hier een binned/gegroepeerd overzicht per wijk en jaar)
p_stapeling <- ggplot(samenvatting_stapeling[n >= MIN_N_ALGEMEEN],
                       aes(x = JAAR, y = gem_stapeling, color = WC)) +
  geom_line() +
  labs(title = "Gemiddelde stapelingsindex per wijk (Amsterdam Oost)",
       y = "Gemiddelde stapelingsindex", x = "Jaar")
ggsave(file.path(OUTPUT_PAD, "stapeling_per_wijk.png"), p_stapeling, width = 8, height = 5)

cat("Klaar. Controleer alle bestanden in", OUTPUT_PAD,
    "handmatig tegen de disclosure-regels (plan §7) vóórdat ze worden aangeboden voor CBS-outputtoetsing.\n")
