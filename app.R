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
choices_source <- unique(dd$source) %>% na.omit() %>% sort()
choices_domain <- if("domain" %in% names(dd)) unique(dd$domain) %>% na.omit() %>% sort() else character(0)

# 2. JS Button Config (from ui branch)
table_all_cols <- c("similarity", names(dd))
table_hidden_cols <- setdiff(table_all_cols, "name")
table_hidden_cols_json <- jsonlite::toJSON(table_hidden_cols, auto_unbox = TRUE)

# Mobile view: hide every column except name + label (description)
mobile_hidden_cols <- setdiff(table_all_cols, c("name", "label"))
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
  theme = bs_theme(preset = "flatly"),
  
  tags$head(
    tags$style(HTML("
      .card { height: 100%; }
      .form-group { margin-bottom: 15px; }
      .no-gap { gap: 0 !important; }
      .scrollable-checkboxes {
        max-height: 200px;
        overflow-y: auto;
        padding: 5px;
        border: 1px solid #e9ecef;
        border-radius: 4px;
        background-color: #f8f9fa;
      }
      .filter-actions { font-size: 0.8rem; margin-bottom: 5px; }

      @media (max-width: 768px) {

        /* 1. Allow the page to scroll vertically on mobile
              (page_fillable locks overflow:hidden by default) */
        html, body {
          overflow: auto !important;
          height: auto !important;
        }
        .bslib-page-fill {
          height: auto !important;
          min-height: 100vh !important;
          overflow: visible !important;
        }

        /* 2. Let the outer layout and card grow with content */
        .bslib-sidebar-layout:not(.no-gap),
        .bslib-sidebar-layout:not(.no-gap) > [role='main'] {
          height: auto !important;
          overflow: visible !important;
        }
        .card:has(.bslib-sidebar-layout.no-gap) {
          height: auto !important;
          min-height: 0 !important;
          overflow: visible !important;
        }

        /* 3. Switch the inner (right-sidebar) layout from CSS grid to flex column
              so the table sits on TOP and the filter panel stacks BELOW */
        .bslib-sidebar-layout.no-gap,
        .bslib-sidebar-layout.sidebar-right.no-gap {
          display: flex !important;
          flex-direction: column !important;
          height: auto !important;
          min-height: 0 !important;
          overflow: visible !important;
        }

        /* 4. Table area: full width, fixed scrollable height */
        .bslib-sidebar-layout.no-gap > [role='main'],
        .bslib-sidebar-layout.no-gap > .bslib-main {
          order: 1 !important;
          width: 100% !important;
          height: 55vh !important;
          min-height: 200px !important;
          overflow: auto !important;
          grid-column: unset !important;
        }

        /* 5. Right sidebar: full width, stacked below, always visible */
        .bslib-sidebar-layout.no-gap > aside,
        .bslib-sidebar-layout.no-gap > .bslib-sidebar {
          display: block !important;   /* override any bslib-injected display:none */
          order: 2 !important;
          width: 100% !important;
          max-width: 100% !important;
          height: auto !important;
          max-height: none !important;
          overflow-y: auto !important;
          border-left: none !important;
          border-top: 1px solid #dee2e6 !important;
          grid-column: unset !important;
        }

        /* 6. Keep the bslib collapse toggle visible on mobile so users can
              re-open the right filter panel after it auto-hides on search. */
        .no-gap .collapse-toggle {
          display: flex !important;
          z-index: 5;
        }

        /* 7. Cap the reactable so it doesn't overflow its container */
        #results_table {
          height: 55vh !important;
        }

        /* 8. Compact, mobile-friendly table cells */
        #results_table .rt-td,
        #results_table .rt-th {
          padding: 4px 6px !important;
          font-size: 0.8rem !important;
          line-height: 1.25 !important;
        }
        #results_table .rt-td {
          white-space: normal !important;
          word-break: break-word !important;
        }
        /* Hide pagination summary text — keep the page buttons */
        #results_table .rt-page-info,
        #results_table .rt-page-size {
          display: none !important;
        }
        /* Tighten the global search box */
        #results_table .rt-search {
          font-size: 0.85rem !important;
          margin-bottom: 4px !important;
        }

        /* 9. When bslib marks the right sidebar closed, fully hide it
              (our flex-column override would otherwise keep it visible). */
        .bslib-sidebar-layout.no-gap[data-bslib-sidebar-open='closed'] > aside,
        .bslib-sidebar-layout.no-gap[data-bslib-sidebar-open='closed'] > .bslib-sidebar,
        .bslib-sidebar-layout.no-gap > .bslib-sidebar[aria-hidden='true'],
        .bslib-sidebar-layout.no-gap > aside[aria-hidden='true'] {
          display: none !important;
        }
        /* And when closed, let the table area take all available height */
        .bslib-sidebar-layout.no-gap[data-bslib-sidebar-open='closed'] > [role='main'],
        .bslib-sidebar-layout.no-gap[data-bslib-sidebar-open='closed'] > .bslib-main {
          height: auto !important;
          min-height: 70vh !important;
        }

        /* 10. Make the row-details modal fit narrow screens */
        .modal-dialog,
        .modal-dialog.modal-lg {
          margin: 0.5rem !important;
          max-width: calc(100% - 1rem) !important;
        }
        .modal-body { padding: 0.75rem !important; }
      }

      /* Row-details modal table: wrap long values, full width */
      .row-details-table { table-layout: fixed; width: 100%; }
      .row-details-table th,
      .row-details-table td {
        word-break: break-word;
        overflow-wrap: anywhere;
        white-space: normal;
        vertical-align: top;
      }
      .row-details-table th { width: 30%; }

      /* Visual cue that rows are clickable */
      #results_table .rt-tr:not(.rt-tr-header):not(.rt-tr-filter) { cursor: pointer; }
    ")),
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

      // After the results table renders on mobile, hide all columns
      // except `name` and `label` to keep the view minimal.
      var MOBILE_HIDDEN = ", mobile_hidden_cols_json, ";
      $(document).on('shiny:value', function(event) {
        if (event.name !== 'results_table') return;
        if (!window.matchMedia('(max-width: 768px)').matches) return;
        setTimeout(function() {
          try { Reactable.setHiddenColumns('results_table', MOBILE_HIDDEN); }
          catch (e) { /* table not ready yet */ }
        }, 200);
      });

    ")))
  ),
  
  title = "ABCD Semantic Search",
  
  # Header
  div(
    class = "bg-primary text-white p-3 rounded-2 mb-2",
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
                h6("Actions", class = "fw-bold text-uppercase text-secondary small"),
                
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
                
                # Show only name (JS Version from ui)
                tags$button(
                  "Show only name column",
                  class = "btn btn-secondary w-100",
                  onclick = paste0(
                    "Reactable.setHiddenColumns('results_table', function(prevColumns) { ",
                    "return prevColumns.length === 0 ? ",
                    table_hidden_cols_json,
                    " : [] })"
                  )
                )
              ),
              
              # 2. Filters (HEAD - Preserved as requested)
              h6("Filters", class = "fw-bold text-uppercase text-secondary small"),
              accordion(
                open = c("Source", "Domain"), 
                
                accordion_panel(
                  "Source",
                  div(class = "filter-actions",
                      actionLink("all_source", "Select All"), " | ",
                      actionLink("none_source", "Deselect All")
                  ),
                  div(
                    class = "scrollable-checkboxes",
                    checkboxGroupInput("filter_source", label = NULL, 
                                       choices = choices_source, 
                                       selected = choices_source)
                  )
                ),
                
                accordion_panel(
                  "Domain",
                  div(class = "filter-actions",
                      actionLink("all_domain", "Select All"), " | ",
                      actionLink("none_domain", "Deselect All")
                  ),
                  div(
                    class = "scrollable-checkboxes",
                    checkboxGroupInput("filter_domain", label = NULL, 
                                       choices = choices_domain, 
                                       selected = choices_domain)
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
          relocate(similarity, name, label)
        
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
  filtered_data <- reactive({
    data <- master_results()
    
    if (nrow(data) == 0) return(data)
    
    # Source Filter
    if (!is.null(input$filter_source)) {
      data <- data %>% filter(source %in% input$filter_source)
    } else {
      return(data[0,])
    }
    
    # Domain Filter
    if ("domain" %in% names(data) && !is.null(input$filter_domain)) {
      data <- data %>% filter(domain %in% input$filter_domain)
    } else if ("domain" %in% names(data)) {
      return(data[0,])
    }
    
    data
  })
  
  # --- 3. HELPER EVENTS ---
  observeEvent(input$all_source, updateCheckboxGroupInput(session, "filter_source", selected = choices_source))
  observeEvent(input$none_source, updateCheckboxGroupInput(session, "filter_source", selected = character(0)))
  
  observeEvent(input$all_domain, updateCheckboxGroupInput(session, "filter_domain", selected = choices_domain))
  observeEvent(input$none_domain, updateCheckboxGroupInput(session, "filter_domain", selected = character(0)))
  
  # --- 4. TABLE RENDER ---
  output$results_table <- reactable::renderReactable({
    req(nrow(filtered_data()) > 0)
    data <- filtered_data()
    
    reactable::reactable(
      data,
      # Note: no `elementId` — Shiny uses the output id ("results_table")
      # as the DOM id automatically. Setting it again triggers a warning.
      columns = list(
        label = reactable::colDef(minWidth = 450, name = "Description"),
        name = reactable::colDef(minWidth = 200, name = "Variable Name"),
        similarity = reactable::colDef(minWidth = 100, name = "Score"),
        source = reactable::colDef(minWidth = 150),
        domain = reactable::colDef(minWidth = 150)
      ),
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
  
  # --- 5. DELETE ROW LOGIC ---
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

  # --- 5b. ROW CLICK → DETAILS MODAL ---
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