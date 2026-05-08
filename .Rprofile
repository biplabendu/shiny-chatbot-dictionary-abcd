if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv")
}

source("renv/activate.R")


# Force reticulate to use OUR local python environment
# We check for the directory to avoid errors if it doesn't exist yet
if (dir.exists("python_env")) {
  # Mac/Linux path
  if (Sys.info()[['sysname']] != "Windows") {
    Sys.setenv(RETICULATE_PYTHON = file.path(getwd(), "python_env", "bin", "python"))
  } else {
    # Windows path
    Sys.setenv(RETICULATE_PYTHON = file.path(getwd(), "python_env", "Scripts", "python.exe"))
  }
  
  message(paste("-> Python configured:", Sys.getenv("RETICULATE_PYTHON")))
}
