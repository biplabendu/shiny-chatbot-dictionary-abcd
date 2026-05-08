# Running it on your computer

This section describes how to run the application on your local machine.

> The instructions below were tested on macOS (OSX).


## Getting the repository

You can obtain the repository by cloning it from GitHub:

```
git clone https://github.com/biplabendu/abcd-dictionary-chatbot
```

### Alternative: Download as a ZIP

If you prefer not to use Git, you can download the repository as a ZIP file:

1. Go to the repository page: https://github.com/biplabendu/abcd-dictionary-chatbot
2. Click the Code button.
3. Select Download ZIP.
4. Extract the ZIP archive to a location of your choice.


## Software requirements

**This application uses both R and Python, so you will need to install and configure dependencies for both environments.**

### R setup

You can run the R components using either:
- the R command-line interface (CLI), or
- RStudio.

Instructions are provided for both options below — **you only need to follow one**.


#### Option A: R Command Line Interface (CLI)

1. Install R

   If R is not already installed, download and install R version 4.5 or above from [this page](https://cran.rstudio.com/)

2. Navigate to the app directory

   From your terminal, move to the application directory:
   ```
   cd abcd-dictionary-chatbot/dev/app-v1
   ```
3. Start the `R` interpreter

   ```
   R
   ```
   **Note:** If you see "Error: could not find function "install.package"", you should try running `install.packages("renv")`

4. Install required `R` packages:

   Inside the `R` session, restore the project environment using renv:
   ```R
   renv::restore()
   ```   
   This will install all required R dependencies defined for the project.

#### Option B: RStudio (alternative)
If you prefer to use RStudio:

1. Install R

   If R is not already installed, download and install R version 4.5 or above from [this page](https://cran.rstudio.com/)

2. Install `Rstudio`

   Install `Rstudio` from [here](https://posit.co/download/rstudio-desktop/)

3. Open `Rstudio`

4. Open the app in `Rstudio`

   Double click the `app-v1.Rproj` file

5.  Run `renv::restore()` to install necessary packages


### Python setup

Your system likely already has Python installed. You can verify this by checking the Python executable and version in your terminal.

1. Check the Python installation

   ```
   which python # should return a path
   python --version
   ```
   The Python version should be 3.11 or newer. If you don't have `Python`, download and install from [here](https://www.python.org/downloads/).

2. Navigate to the app directory

   From your terminal, move to the application directory:
   ```
   cd abcd-dictionary-chatbot/dev/app-v1
   ```
   
3. Create a Python virtual environment

   Create and activate a Python virtual environment, then install the required packages:
   ```
   python3 -m venv python_env
   source python_env/bin/activate
   pip install -r requirements.txt
   ```

## Run the app locally
You can run the application locally using either the `R` command-line interface (CLI) or `RStudio`.

### Option A: R Command Line Interface (CLI)

1. Start the `R` interpreter from the application directory:

   ```
   R
   ```
2. Run the app in the R interpreter:

   ```R
   shiny::runApp()
   ```

### Option B: RStudio
1. Open `RStudio`.
2. Double-click the `app-v1.Rproj` file to open the project.
3. Open the `app.R` file.
4. Click Run App in the top-right corner of the script editor.

### Notes

- Ensure that all R and Python dependencies have been installed before running the app.
- The application will open in a web browser once it starts.
