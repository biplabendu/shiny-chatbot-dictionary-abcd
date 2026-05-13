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

# --- FILE SETUP ---
dictionary_path <- "data/dd-abcd-6_0.parquet"
if (!file.exists(dictionary_path)) {
  stop(paste("Missing", dictionary_path,
             "- run ./setup.sh to build artifacts."))
}

# On shinyapps.io, build the Python virtualenv on first launch (cached on
# subsequent boots of the same instance). Locally we use python_env/ via .Rprofile.
if (Sys.info()[["user"]] == "shiny") {
  venv <- Sys.getenv("VIRTUALENV_NAME")
  reticulate::virtualenv_create(envname = venv,
                                python  = Sys.getenv("PYTHON_PATH"))
  reticulate::virtualenv_install(venv,
                                 packages = readLines("requirements.txt"),
                                 ignore_installed = TRUE)
  reticulate::use_virtualenv(venv, required = TRUE)
}

# Source python script
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
        max_height: 200px;
        overflow-y: auto;
        padding: 5px;
        border: 1px solid #e9ecef;
        border-radius: 4px;
        background-color: #f8f9fa;
      }
      .filter-actions { font-size: 0.8rem; margin-bottom: 5px; }
    ")),
    tags$script(HTML("
      $(document).on('keydown', '#search_query', function(e) {
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault();
          $('#run_search').click();
        }
      });
    "))
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


 # Show persistent notification if embeddings don't yet exist for selected model.
 # The Sys.sleep below flushes it to the browser before the blocking Python call.
 emb_file <- if (isolate(input$choose_model) == "no_img") {
   "data/local_embeddings/embeddings_all-MiniLM-L6-v2_noimag.npy"
 } else {
   "data/local_embeddings/embeddings_all-MiniLM-L6-v2.npy"
 }
 emb_notif_id <- if (!file.exists(emb_file)) {
   showNotification(
     ui = tagList(
       tags$strong("Building embeddings for the first time."),
            "This may take several minutes — please wait."
          ),
          duration = NULL,
          type = "message",
          closeButton = FALSE
        )                                                                                                                                               
      } else {
        NULL
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
      if (!is.null(emb_notif_id)) removeNotification(emb_notif_id)
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
      elementId = "results_table", # Required for JS Download button
      columns = list(
        label = reactable::colDef(minWidth = 450, name = "Description"),
        name = reactable::colDef(minWidth = 200, name = "Variable Name"),
        similarity = reactable::colDef(minWidth = 100, name = "Score"),
        source = reactable::colDef(minWidth = 150),
        domain = reactable::colDef(minWidth = 150)
      ),
      selection = "multiple",
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
  
  # --- 6. OUTPUTS ---
  output$table_counts <- renderText({
    paste("Showing", nrow(filtered_data()), "variables")
  })
}

shinyApp(ui, server)