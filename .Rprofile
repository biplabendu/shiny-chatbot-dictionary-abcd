# rsconnect excludes renv/ from the deploy bundle (its own hardcoded rule),
# so on shinyapps.io there is no activate.R to source. Skip silently there
# and let shinyapps.io's own renv.lock-driven install do the work.
if (file.exists("renv/activate.R")) {
  if (!requireNamespace("renv", quietly = TRUE)) {
    install.packages("renv")
  }
  source("renv/activate.R")
}


# Local dev: point reticulate at python_env/. On shinyapps.io, Connect's
# manifest-based provisioning sets RETICULATE_PYTHON itself, so we skip this.
if (Sys.info()[["user"]] != "shiny" && dir.exists("python_env")) {
  if (Sys.info()[["sysname"]] != "Windows") {
    Sys.setenv(RETICULATE_PYTHON = file.path(getwd(), "python_env", "bin", "python"))
  } else {
    Sys.setenv(RETICULATE_PYTHON = file.path(getwd(), "python_env", "Scripts", "python.exe"))
  }
  message(paste("-> Python configured:", Sys.getenv("RETICULATE_PYTHON")))
}
