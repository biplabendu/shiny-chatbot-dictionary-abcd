library(shiny)
library(dplyr)
library(stringr)
library(reticulate)
library(reactable)
library(bslib)
library(fontawesome)
library(nanoparquet)
library(cicerone)

# --- ENVIRONMENT CONFIG ---
options(shiny.autoreload = TRUE)
options(shiny.autoreload.legacy_warning = FALSE)  # silence "install watcher" nag

# --- FILE SETUP ---
# config.yml is the single source of truth for which dictionary release the
# embeddings were built against — keeping the R UI in lockstep with the
# Python pipeline. To switch dictionaries, edit config.yml and re-run setup.sh.
config <- yaml::read_yaml("config.yml")
dictionary_path <- file.path("data", config$dictionary$parquet)
if (!file.exists(dictionary_path)) {
  stop(paste("Missing", dictionary_path,
             "- run ./setup.sh to build artifacts."))
}

# Guard against config.yml/embeddings drift: build_embeddings.py writes the
# parquet it built against into data/embeddings/manifest.txt. If config.yml
# was edited (e.g. bumped to 7.0) but setup.sh wasn't re-run, the embeddings
# on disk are still for the previous release — searches return rows from the
# old dictionary while the UI displays the new version. Refuse to start
# instead of producing erroneous results / titles.
manifest_path <- "data/embeddings/manifest.txt"
if (!file.exists(manifest_path)) {
  stop(paste("Missing", manifest_path,
             "- run ./setup.sh to (re)build embeddings."))
}
built_parquet <- trimws(readLines(manifest_path, warn = FALSE)[1])
if (!identical(built_parquet, config$dictionary$parquet)) {
  stop(sprintf(
    "Embeddings/config mismatch: config.yml points to '%s' but embeddings were built for '%s'. Run ./setup.sh to rebuild.",
    config$dictionary$parquet, built_parquet))
}

# Extract version from filename (e.g. dd-abcd-7_0.parquet -> "7.0").
dictionary_version <- sub(".*dd-abcd-([0-9]+)_([0-9]+)\\.parquet$", "\\1.\\2",
                          basename(dictionary_path))

# Python deps for reticulate's auto-installer (uv-based). On shinyapps.io,
# reticulate downloads a pre-built CPython + these packages on first run.
# Locally, .Rprofile points RETICULATE_PYTHON at python_env/ and py_require
# is a no-op.
reticulate::py_require(readLines("requirements.txt"))

source_python("python/backend.py")

# Load dictionary for R-side lookups and filter population
dd <- nanoparquet::read_parquet(dictionary_path) %>%
  dplyr::mutate(dplyr::across(dplyr::everything(), as.character))

# --- DATA PREP & CONFIG ---
# 1. UI Filter Choices (from HEAD logic)
choices_source   <- unique(dd$source) %>% na.omit() %>% sort()
choices_domain   <- if ("domain"   %in% names(dd)) unique(dd$domain)   %>% na.omit() %>% sort() else character(0)
choices_type_var <- if ("type_var" %in% names(dd)) unique(dd$type_var) %>% na.omit() %>% sort() else character(0)

# 2. JS Button Config (from ui branch)
table_all_cols <- c("similarity", names(dd))

# Desktop view: curated 8 columns in this order. On row click, the modal
# still shows every column (the visible 8 first, then the rest).
desktop_visible_cols <- c(
  "similarity", "name", "label",
  "domain", "sub_domain", "source", "type_var", "type_level"
)
desktop_visible_cols     <- intersect(desktop_visible_cols, table_all_cols)
desktop_hidden_cols      <- setdiff(table_all_cols, desktop_visible_cols)
desktop_hidden_cols_json <- jsonlite::toJSON(desktop_hidden_cols, auto_unbox = TRUE)

# Mobile view: hide every column except name + label (description)
mobile_hidden_cols      <- setdiff(table_all_cols, c("name", "label"))
mobile_hidden_cols_json <- jsonlite::toJSON(mobile_hidden_cols, auto_unbox = TRUE)

# 3. Domain Logic (from ui branch)
domain_all <- c(
  'ABCD (General)','COVID-19','Endocannabinoid',
  'Friends, Family, & Community','Genetics','Hurricane Irma',
  'Imaging','Linked External Data','MR Spectroscopy','Mental Health',
  'Neurocognition','Novel Technologies','Physical Health',
  'Social Development','Substance Use')

# --- UI ---
ui <- page_fillable(
  # Brand palette + typography matches docs/stylesheets/extra.css (mkdocs site).
  # Bootstrap SASS retints buttons / .bg-primary / links / etc. automatically.
  theme = bs_theme(
    preset      = "flatly",
    primary     = "#62272D",   # burgundy
    secondary   = "#FDBF6F",   # warm orange
    info        = "#DEEBF7",   # pale blue
    warning     = "#FF7F00",   # orange
    danger      = "#E31A1C",   # red
    success     = "#33A02C",   # green
    base_font   = bslib::font_google("Inter"),
    heading_font = bslib::font_google("Inter"),
    code_font   = bslib::font_google("Source Code Pro")
  ),
  
  tags$head(
    # All app styling lives in www/app.css (Shiny serves www/ at the app root).
    # Append the file's mtime as a cache-busting query string so browsers fetch
    # the current CSS after each edit instead of serving a stale cached copy.
    tags$link(
      rel = "stylesheet", type = "text/css",
      href = {
        mt <- suppressWarnings(file.mtime("www/app.css"))
        if (is.na(mt)) "app.css" else paste0("app.css?v=", as.integer(mt))
      }
    ),

    # Inject the data-driven hidden-column config for app.js. This is the only
    # JS built from R values; it's pure JSON assignment (no risky escapes).
    tags$script(HTML(paste0(
      "window.ABCD_HIDDEN = {desktop: ", desktop_hidden_cols_json,
      ", mobile: ", mobile_hidden_cols_json, "};"
    ))),

    # All client-side behavior lives in www/app.js (served at the app root),
    # NOT inlined here — embedding JS in an R string turns every \\n, \\t and \"
    # into an R escape, so a stray backslash silently breaks the whole script.
    # mtime query string busts the browser cache after each edit (see app.css).
    tags$script(
      src = {
        mt <- suppressWarnings(file.mtime("www/app.js"))
        if (is.na(mt)) "app.js" else paste0("app.js?v=", as.integer(mt))
      }
    )
  ),

  # cicerone (driver.js) JS/CSS dependencies for the guided tour.
  use_cicerone(),

  title = paste0("ABCD Semantic Search (", dictionary_version, ")"),

  # Header (brand-burgundy bar — see .app-header in www/app.css)
  div(
    class = "app-header bg-primary text-white p-3 rounded-2 mb-2 d-flex justify-content-between align-items-center",
    h2(paste0("ABCD Data Dictionary Semantic Search (", dictionary_version, ")"),
       class = "m-0"),
    actionButton("start_tour", "Take a tour",
                 icon = icon("circle-question"),
                 class = "btn-light btn-sm flex-shrink-0")
  ),

  layout_sidebar(
    
    # --- LEFT SIDEBAR (Search Inputs) ---
    sidebar = sidebar(
      id = "left_sidebar",
      open = "open",
      width = 320,
      card_header("Search Parameters"),
      
      textAreaInput("search_query", "Describe what you are looking for:",
                    placeholder = "e.g., bullying at school, sleep disorders...",
                    height = "150px"),
      helpText(span(id = "search_query_count", "0 / 250 characters")),

      # [MERGED] Slider with ui branch defaults (value = 0.3)
      # Wrapped in an id'd div because sliderInput puts id="cutoff" on the
      # original <input>, which ionRangeSlider hides (display:none) — a
      # zero-size element the guided tour can't draw a highlight box around.
      # The wrapper gives the tour a visible anchor spanning the whole control.
      div(
        id = "cutoff_step",
        sliderInput("cutoff", "Similarity Threshold:",
                    min = 0.2, max = 1.0, value = 0.3, step = 0.05)
      ),
      
      helpText("Higher values = stricter matching."),
      
      # [MERGED] Search Button + Model Selector from ui branch
      actionButton("run_search", "Search Variables", 
                   class = "btn-primary w-100 mb-2", icon = icon("magnifying-glass")),
      
      # Wrapped in an id'd div so the guided tour has a visible anchor:
      # selectize hides the original <select id="choose_model">, so the tour
      # can't frame it directly (see the cutoff slider wrapper above).
      div(
        id = "choose_model_step",
        selectizeInput(
          "choose_model",
          "Choose your champion:",
          choices = c("ChatBot Pro (no imaging)" = "no_img",
                      "ChatBot Pro Max Ultra (all)" = "all"),
          selected = "no_img",
          multiple = FALSE
        )
      ),

      # [HEAD] Explanatory Text (Preserved for UX)
      div(
        class = "small text-muted border-top pt-3",
        tags$h6("Capabilities:", class = "fw-bold"),
        tags$ul(
          class = "ps-3",
          tags$li("Finds variables by meaning."),
          tags$li("Filters by similarity score.")
        )
      )
    ),
    
    # --- MAIN CONTENT ---
    navset_card_tab(
      nav_panel(
        "Explore",
        card(
          id = "results_card",
          full_screen = TRUE,
          layout_sidebar(
            class = "no-gap",
            
            # --- RIGHT SIDEBAR (Filters & Actions) ---
            sidebar = sidebar(
              id = "right_sidebar",
              position = "right",
              open = "open",
              width = 350,
              card_header("Refine Results"),
              
              # 1. Action Buttons (Merged HEAD delete with ui Download/Hide)
              div(
                class = "mb-4 border-bottom pb-3 d-flex flex-column gap-2",
                h6("Actions", class = "fw-bold text-uppercase text-primary small"),
                
                # Delete Row (HEAD)
                actionButton(
                  "delete_selected_rows",
                  "Delete Selected Rows",
                  class = "btn-outline-danger w-100",
                  icon = icon("trash")
                ),
                
                # Download CSV (JS Version from ui)
                tags$button(
                  tagList(fontawesome::fa("download"), "Download as CSV"),
                  id = "download_csv_btn",
                  class = "btn btn-success w-100",
                  onclick = "(function(){var state=Reactable.getState('results_table')||{};var hidden=state.hiddenColumns||[];var all=state.columns?state.columns.map(function(c){return c.id;}):Object.keys((state.data&&state.data[0])||{});var visible=all.filter(function(id){return hidden.indexOf(id)===-1;});Reactable.downloadDataCSV('results_table','search_results.csv',{columnIds:visible});})()"
                ),
                
                # Copy the current results' variable names to the clipboard,
                # one per line (see copyVariableNames() in the head script).
                tags$button(
                  tagList(fontawesome::fa("clipboard"), "Copy Variable Names"),
                  id = "copy_names_btn",
                  class = "btn btn-secondary w-100",
                  onclick = "copyVariableNames(this)"
                )
              ),
              
              # 2. Filters — searchable multi-select dropdowns.
              # Empty selection = no filter applied (include all rows).
              h6("Filters", class = "fw-bold text-uppercase text-primary small"),

              # Each filter is wrapped in an id'd div so the guided tour can
              # frame the visible selectize control (the id lives on the hidden
              # <select>; see the cutoff slider / model wrappers above).
              div(
                id = "filter_source_step",
                selectizeInput(
                  "filter_source",
                  label = "Source",
                  choices = choices_source,
                  selected = NULL,
                  multiple = TRUE,
                  options = list(
                    plugins = list("remove_button"),
                    placeholder = "All sources (click to filter)"
                  )
                )
              ),

              div(
                id = "filter_domain_step",
                selectizeInput(
                  "filter_domain",
                  label = "Domain",
                  choices = choices_domain,
                  selected = NULL,
                  multiple = TRUE,
                  options = list(
                    plugins = list("remove_button"),
                    placeholder = "All domains (click to filter)"
                  )
                )
              ),

              div(
                id = "filter_type_var_step",
                selectizeInput(
                  "filter_type_var",
                  label = "Variable Type",
                  choices = choices_type_var,
                  selected = NULL,
                  multiple = TRUE,
                  options = list(
                    plugins = list("remove_button"),
                    placeholder = "All types (click to filter)"
                  )
                )
              )
            ),
            
            # --- TABLE DISPLAY ---
            div(
              reactableOutput("results_table", width = "100%", height = "100%"),
              div(class = "text-muted small p-2", textOutput("table_counts"))
            ),
            fill = TRUE
          )
        )
      ),
      
      # [MERGED] Additional Info Tab from ui branch
      nav_panel(
        "Additional Info",
        div(
          class = "p-3",
          h5("Load results and create dataset in NBDCtools"),
          tags$pre(
            tags$code(
              paste(
                "library(readr)",
                "library(NBDCtools)",
                "",
                "search_results <- read_csv('search_results.csv')",
                "data <- create_dataset(",
                "  study = 'abcd',",
                "  data_dir = '<Path To Your Raw Data>',",
                "  vars = search_results$name",
                ")",
                sep = "\n"
              )
            )
          )
        )
      )
    ),
    fill = TRUE
  )
)

# --- GUIDED TOUR (cicerone) ---
# Defined at top level: the object is stateless config and is reusable across
# sessions. Steps anchor to stable element IDs added in the UI above.
guide <- Cicerone$
  new()$
  step("start_tour",
       "Guided tour",
       "Welcome! This quick tour walks you through every control for searching the ABCD data dictionary. You can relaunch it anytime from this button.",
       position = "left")$
  step("search_query",
       "Describe what you need",
       "Type a plain-language description of the variables you're looking for, e.g. 'bullying at school'.",
       position = "right")$
  step("cutoff_step",
       "Similarity threshold",
       "Raise this to return stricter, more relevant matches; lower it to cast a wider net.",
       position = "right")$
  step("choose_model_step",
       "Choose your model",
       "Pick which embedding model powers the search. 'No imaging' skips imaging variables; the 'all' model searches the full dictionary.",
       position = "right")$
  step("run_search",
       "Run the search",
       "Click here to find the variables that best match your description.",
       position = "right")$
  step("right_sidebar",
       "Refine your results",
       "This panel holds the actions and filters you use to shape your results once a search returns.",
       position = "left")$
  step("delete_selected_rows",
       "Remove rows",
       "Select rows in the table, then click here to drop them from your current result set.",
       position = "left")$
  step("download_csv_btn",
       "Export to CSV",
       "Download your (filtered) results as a CSV for use in NBDCtools or your own analysis.",
       position = "left")$
  step("copy_names_btn",
       "Copy variable names",
       "Copy your current results' variable names to the clipboard, one per line — ready to paste into a script or NBDCtools.",
       position = "left")$
  step("filter_source_step",
       "Filter by source",
       "Narrow results to one or more data sources. Leave empty to include every source.",
       position = "left")$
  step("filter_domain_step",
       "Filter by domain",
       "Restrict results to specific domains. Leave empty to include every domain.",
       position = "left")$
  step("filter_type_var_step",
       "Filter by variable type",
       "Restrict results to specific variable types. Leave empty to include every type.",
       position = "left")

# --- SERVER ---
server <- function(input, output, session) {

  # --- GUIDED TOUR ---
  # Attach the tour config to this session before it can be started.
  guide$init()

  # Auto-start on a user's first ever visit. input$tour_seen arrives once per
  # connect (see the localStorage JS bridge in the UI head block); once = TRUE
  # guards against the observer re-firing within a session.
  observeEvent(input$tour_seen, {
    if (isFALSE(input$tour_seen)) {
      guide$start()
      # Mark this browser so the tour won't auto-start on future visits.
      session$sendCustomMessage("mark_tour_seen", TRUE)
    }
  }, once = TRUE)

  # Re-launch on demand from the header button.
  observeEvent(input$start_tour, {
    guide$start()
  })

  
  # Store the "Master" search result (before manual filtering)
  master_results <- reactiveVal(dd[0, ])
  
  # --- 1. SEARCH EVENT ---
  observeEvent(input$run_search, {
    req(input$search_query)

    # Enforce the 250-character cap server-side (the client-side JS is best-effort).
    if (nchar(input$search_query) > 250) {
      showNotification(
        "Please limit your query to 250 characters or fewer.",
        type = "error"
      )
      return()
    }

    # On mobile, auto-collapse BOTH sidebars so the table fills the screen.
    # The bslib collapse-toggle (small arrow on each sidebar's edge) lets
    # users re-open either panel.
    if (isTRUE(isolate(input$window_width) <= 768)) {
      bslib::toggle_sidebar("left_sidebar",  open = FALSE, session = session)
      bslib::toggle_sidebar("right_sidebar", open = FALSE, session = session)
    }

    # Show a modal, wait 1 second, then remove it
    showModal(modalDialog(
      title = NULL,
      "Searching...",
      footer = NULL,
      size = "s",
      easyClose = FALSE
    ))
    Sys.sleep(1) # Keeps the box visible for 1 second
    removeModal()

    # Visual Feedback (Spinner on button)
    updateActionButton(session, "run_search", label = "Searching...", icon = icon("spinner", class = "fa-spin"))
    on.exit({
      updateActionButton(session, "run_search", label = "Search Variables", icon = icon("magnifying-glass"))
    })
    
    tryCatch({
      
      # [MERGED] Call Python Backend with 'domains_list' logic from ui branch
      res <- semantic_search(
        isolate(input$search_query), 
        data_path = "data", 
        cutoff = isolate(input$cutoff),
        domains_list = if (isolate(input$choose_model) == "no_img") {
          NULL
        } else {
          domain_all
        }
      )
      
      # [MERGED] Result processing from ui branch (Indices + String cleanup)
      indices <- res[[2]]
      similarities <- res[[1]]
      
      if (length(indices) > 0) {
        # Extract rows (Python 0-based index -> R 1-based index
        raw_df <- {if (isolate(input$choose_model) == "no_img") {
          dd |> filter(!domain %in% c('Imaging'))
        } else {
          dd
        }} %>%
          .[indices + 1, ] %>%
          mutate(similarity = round(similarities, 3)) %>%
          mutate(across(where(is.character), ~ stringr::str_replace_all(.x, "[\r\n]+", " "))) %>%
          # Put the 8 curated columns first so both the desktop table AND
          # the row-click modal show them in this order; other columns follow.
          relocate(any_of(desktop_visible_cols))
        
        master_results(raw_df)
        
        showNotification(paste("Found", nrow(raw_df), "variables."), type = "message")
      } else {
        master_results(dd[0, ])
        showNotification("No matches found. Try lowering the Similarity Threshold.", type = "warning")
      }
      
    }, error = function(e) {
      showNotification("Python Error", type = "error")
      print(e)
    })
  })
  
  # --- 2. FILTERING LOGIC ---
  # Empty selection on any filter = no filter applied for that dimension
  # (include all values). Pick one or more to narrow the results.
  filtered_data <- reactive({
    data <- master_results()
    if (nrow(data) == 0) return(data)

    if (length(input$filter_source) > 0) {
      data <- data %>% filter(source %in% input$filter_source)
    }
    if ("domain" %in% names(data) && length(input$filter_domain) > 0) {
      data <- data %>% filter(domain %in% input$filter_domain)
    }
    if ("type_var" %in% names(data) && length(input$filter_type_var) > 0) {
      data <- data %>% filter(type_var %in% input$filter_type_var)
    }

    data
  })


  # --- 3. TABLE RENDER ---
  output$results_table <- reactable::renderReactable({
    req(nrow(filtered_data()) > 0)
    data <- filtered_data()

    # Curated desktop columns (visible by default, custom display names) +
    # every other column with show = FALSE so it's available for the
    # row-click modal but not rendered in the table.
    visible_defs <- list(
      similarity = reactable::colDef(name = "Score",         minWidth = 80),
      name       = reactable::colDef(name = "Variable Name", minWidth = 180),
      label      = reactable::colDef(name = "Description",   minWidth = 380),
      domain     = reactable::colDef(name = "Domain",        minWidth = 140),
      sub_domain = reactable::colDef(name = "Sub-Domain",    minWidth = 140),
      source     = reactable::colDef(name = "Source",        minWidth = 120),
      type_var   = reactable::colDef(name = "Type",          minWidth = 100),
      type_level = reactable::colDef(name = "Type Level",    minWidth = 100)
    )
    hidden_defs <- setNames(
      lapply(desktop_hidden_cols, function(.x) reactable::colDef(show = FALSE)),
      desktop_hidden_cols
    )
    column_defs <- c(visible_defs[intersect(names(visible_defs), names(data))], hidden_defs)

    reactable::reactable(
      data,
      # Note: no `elementId` — Shiny uses the output id ("results_table")
      # as the DOM id automatically. Setting it again triggers a warning.
      columns = column_defs,
      selection = "multiple",
      onClick = htmlwidgets::JS(
        "function(rowInfo, column) {",
        "  if (!rowInfo) return;",
        "  // Skip clicks on the selection checkbox column",
        "  if (column && column.id && String(column.id).indexOf('selection') !== -1) return;",
        "  Shiny.setInputValue('row_clicked_idx', rowInfo.index, {priority: 'event'});",
        "}"
      ),
      searchable = TRUE,
      resizable = TRUE,
      filterable = TRUE,
      pagination = TRUE,
      highlight = TRUE,
      bordered = TRUE,
      striped = TRUE,
      height = "75vh",
      theme = reactableTheme(
        rowSelectedStyle = list(backgroundColor = "#e6f3ff", boxShadow = "inset 2px 0 0 0 #007bc2")
      )
    )
  })
  
  # --- 4. DELETE ROW LOGIC ---
  observeEvent(input$delete_selected_rows, {
    selected_indices <- reactable::getReactableState("results_table", "selected")
    
    if (is.null(selected_indices) || length(selected_indices) == 0) {
      showNotification("No rows selected.", type = "warning")
      return()
    }
    
    current_view <- filtered_data()
    vars_to_remove <- current_view$name[selected_indices]
    
    current_master <- master_results()
    new_master <- current_master %>% filter(!name %in% vars_to_remove)
    
    master_results(new_master)
    showNotification("Selected rows deleted.", type = "message")
  })

  # --- 5. ROW CLICK → DETAILS MODAL ---
  observeEvent(input$row_clicked_idx, {
    idx <- as.integer(input$row_clicked_idx) + 1L  # JS 0-based -> R 1-based
    data <- filtered_data()
    if (length(idx) != 1 || is.na(idx) || idx < 1 || idx > nrow(data)) return()

    row <- data[idx, , drop = FALSE]
    fields <- names(row)
    values <- vapply(row, function(x) {
      v <- as.character(x)
      if (length(v) == 0 || is.na(v) || !nzchar(v)) "" else v
    }, character(1))

    details_tbl <- tags$table(
      class = "table table-striped table-sm mb-0 row-details-table",
      tags$tbody(
        lapply(seq_along(fields), function(i) {
          tags$tr(
            tags$th(scope = "row", fields[i]),
            tags$td(
              if (nzchar(values[i])) values[i] else tags$span(class = "text-muted", "—")
            )
          )
        })
      )
    )

    title_str <- if ("name" %in% fields && nzchar(values[match("name", fields)])) {
      paste("Variable:", values[match("name", fields)])
    } else {
      "Row details"
    }

    showModal(modalDialog(
      title = title_str,
      details_tbl,
      size = "l",
      easyClose = TRUE,
      footer = modalButton("Close")
    ))
  })


  # --- 6. OUTPUTS ---
  output$table_counts <- renderText({
    paste("Showing", nrow(filtered_data()), "variables")
  })
}

shinyApp(ui, server)