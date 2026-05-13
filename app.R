library(shiny)
library(dplyr)
library(stringr)
library(reticulate)
library(reactable)
library(bslib)
library(fontawesome)
library(nanoparquet)

# --- ENVIRONMENT CONFIG ---
options(shiny.autoreload = TRUE)
options(shiny.autoreload.legacy_warning = FALSE)  # silence "install watcher" nag

# --- FILE SETUP ---
dictionary_path <- "data/dd-abcd-6_0.parquet"
if (!file.exists(dictionary_path)) {
  stop(paste("Missing", dictionary_path,
             "- run ./setup.sh to build artifacts."))
}

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
table_hidden_cols <- setdiff(table_all_cols, "name")
table_hidden_cols_json <- jsonlite::toJSON(table_hidden_cols, auto_unbox = TRUE)

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
    tags$link(rel = "stylesheet", type = "text/css", href = "app.css"),

    tags$script(HTML(paste0("
      $(document).on('keydown', '#search_query', function(e) {
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault();
          $('#run_search').click();
        }
      });

      // Report viewport width to Shiny so the server can branch on mobile.
      function _reportWidth() {
        if (window.Shiny && Shiny.setInputValue) {
          Shiny.setInputValue('window_width', window.innerWidth, {priority: 'event'});
        }
      }
      $(document).on('shiny:connected', _reportWidth);
      $(window).on('resize', _reportWidth);

      // After the results table renders, apply the viewport-appropriate
      // hidden-columns set so the table state is explicit (the CSV-download
      // button reads state.hiddenColumns).
      //   Desktop: hide everything except the curated 8 columns.
      //   Mobile:  hide everything except `name` and `label`.
      var DESKTOP_HIDDEN = ", desktop_hidden_cols_json, ";
      var MOBILE_HIDDEN  = ", mobile_hidden_cols_json, ";
      $(document).on('shiny:value', function(event) {
        if (event.name !== 'results_table') return;
        setTimeout(function() {
          try {
            var hidden = window.matchMedia('(max-width: 768px)').matches
                       ? MOBILE_HIDDEN
                       : DESKTOP_HIDDEN;
            Reactable.setHiddenColumns('results_table', hidden);
          } catch (e) { /* table not ready yet */ }
        }, 150);
      });

    ")))
  ),
  
  title = "ABCD Semantic Search",
  
  # Header (brand-burgundy bar — see .app-header in www/app.css)
  div(
    class = "app-header bg-primary text-white p-3 rounded-2 mb-2",
    h2("ABCD Data Dictionary Semantic Search", class = "m-0")
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
      
      # [MERGED] Slider with ui branch defaults (value = 0.3)
      sliderInput("cutoff", "Similarity Threshold:", 
                  min = 0.2, max = 1.0, value = 0.3, step = 0.05),
      
      helpText("Higher values = stricter matching."),
      
      # [MERGED] Search Button + Model Selector from ui branch
      actionButton("run_search", "Search Variables", 
                   class = "btn-primary w-100 mb-2", icon = icon("magnifying-glass")),
      
      selectizeInput(
        "choose_model",
        "Choose your champion:",
        choices = c("ChatBot Pro (no imaging)" = "no_img",
                    "ChatBot Pro Max Ultra (all)" = "all"),
        selected = "no_img",
        multiple = FALSE
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
                  class = "btn btn-success w-100",
                  onclick = "(function(){var state=Reactable.getState('results_table')||{};var hidden=state.hiddenColumns||[];var all=state.columns?state.columns.map(function(c){return c.id;}):Object.keys((state.data&&state.data[0])||{});var visible=all.filter(function(id){return hidden.indexOf(id)===-1;});Reactable.downloadDataCSV('results_table','search_results.csv',{columnIds:visible});})()"
                ),
                
                # Toggle "name only" ↔ default 8-column view
                tags$button(
                  "Show only name column",
                  class = "btn btn-secondary w-100",
                  onclick = paste0(
                    "(function(){",
                    "var ONLY_NAME=", table_hidden_cols_json, ";",
                    "var DEFAULT=",   desktop_hidden_cols_json, ";",
                    "Reactable.setHiddenColumns('results_table', function(prev){",
                    "var same=prev.length===ONLY_NAME.length && ",
                    "ONLY_NAME.every(function(c){return prev.indexOf(c)!==-1;});",
                    "return same ? DEFAULT : ONLY_NAME;",
                    "});})()"
                  )
                )
              ),
              
              # 2. Filters — searchable multi-select dropdowns.
              # Empty selection = no filter applied (include all rows).
              h6("Filters", class = "fw-bold text-uppercase text-primary small"),

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
              ),

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
              ),

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

# --- SERVER ---
server <- function(input, output, session) {
  
  # Store the "Master" search result (before manual filtering)
  master_results <- reactiveVal(dd[0, ])
  
  # --- 1. SEARCH EVENT ---
  observeEvent(input$run_search, {
    req(input$search_query)

    # On mobile, auto-collapse BOTH sidebars so the table fills the screen.
    # The bslib collapse-toggle (small arrow on each sidebar's edge) lets
    # users re-open either panel.
    if (isTRUE(isolate(input$window_width) <= 768)) {
      bslib::sidebar_toggle("left_sidebar",  open = FALSE, session = session)
      bslib::sidebar_toggle("right_sidebar", open = FALSE, session = session)
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