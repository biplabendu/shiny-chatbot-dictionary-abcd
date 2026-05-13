if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv")
}

source("renv/activate.R")


VIRTUALENV_NAME <- "abcd_dictionary_env"

if (Sys.info()[["user"]] == "shiny") {
  # shinyapps.io: build a runtime virtualenv at /home/shiny/.virtualenvs/<name>/
  # The actual virtualenv_create/install happens in app.R before source_python().
  Sys.setenv(PYTHON_PATH       = "python3")
  Sys.setenv(VIRTUALENV_NAME   = VIRTUALENV_NAME)
  Sys.setenv(RETICULATE_PYTHON = paste0("/home/shiny/.virtualenvs/",
                                        VIRTUALENV_NAME, "/bin/python"))
} else if (dir.exists("python_env")) {
  # Local dev: point at the in-repo venv.
  if (Sys.info()[["sysname"]] != "Windows") {
    Sys.setenv(RETICULATE_PYTHON = file.path(getwd(), "python_env", "bin", "python"))
  } else {
    Sys.setenv(RETICULATE_PYTHON = file.path(getwd(), "python_env", "Scripts", "python.exe"))
  }
  message(paste("-> Python configured:", Sys.getenv("RETICULATE_PYTHON")))
}
