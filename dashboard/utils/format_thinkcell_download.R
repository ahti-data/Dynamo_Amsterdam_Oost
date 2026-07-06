format_tc_data <- function(df, chart_type = "standaard", category_col, series_col, value_col, x_col = NULL, y_col = NULL) {
  
  library(dplyr)
  library(tidyr)
  
  # ---------- SCATTER / LORENTZ LOGICA ----------
  if (chart_type %in% c("scatter", "lorentz")) {
    # Think-Cell scatter layout: 
    # Kolom 1: Naam/ID van het punt, Kolom 2: X-waarde, Kolom 3: Y-waarde
    tc_matrix <- df %>%
      select(Point_Name = !!sym(series_col), X = !!sym(x_col), Y = !!sym(y_col)) %>%
      distinct() # Voorkom duplicaten
      
    # Cel A1 moet leeg zijn
    colnames(tc_matrix)[1] <- ""
    return(tc_matrix)
  }
  
  # ---------- STANDAARD BAR / LINE LOGICA ----------
  df_clean <- df %>%
    group_by(!!sym(category_col), !!sym(series_col)) %>%
    summarise(tc_value = mean(!!sym(value_col), na.rm = TRUE), .groups = "drop")
  
  tc_matrix <- df_clean %>%
    pivot_wider(
      names_from = !!sym(category_col),
      values_from = tc_value
    )
  
  colnames(tc_matrix)[1] <- ""
  
  # ---------- 100% BAR LOGICA ----------
  if (chart_type == "100_percent") {
    totals <- df_clean %>%
      group_by(!!sym(category_col)) %>%
      summarise(total = sum(tc_value, na.rm = TRUE)) %>%
      pull(total)
    
    total_row <- c("100%=", as.list(totals))
    names(total_row) <- colnames(tc_matrix)
    tc_matrix <- bind_rows(as_tibble(total_row), tc_matrix)
  }
  
  # ---------- WATERFALL LOGICA ----------
  if (chart_type == "waterfall") {
    # Basis is hetzelfde als standaard, maar je voegt hier eventueel logica toe 
    # om de laatste kolom te overschrijven met "e" voor het eindtotaal.
    # Voorbeeld:
    # tc_matrix[[ncol(tc_matrix)]] <- "e"
  }
  
  return(tc_matrix)
}