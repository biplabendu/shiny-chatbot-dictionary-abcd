# Using the app

[TOC]

The app is divided into three main areas: a **left sidebar** for entering your search, a **main results table** (the *Explore* tab) for browsing matches, and a **right sidebar** for refining and exporting what you find. The page header shows the active dictionary release (e.g. *ABCD Data Dictionary Semantic Search (7.0)*), parsed from `config.yml` at startup.

## Guided tour

On your **first visit** a short interactive walkthrough starts automatically, highlighting each control in turn — the search box, similarity slider, model selector, search button, and the refine-panel actions and filters. It runs only once per browser (the "seen" flag is stored in `localStorage`).

To replay it anytime, click **Take a tour** in the top-right of the header.

The tour is desktop-only: on small screens (≤ 768 px) it is disabled and the button is hidden, because the sidebars are collapsed there and its highlight boxes would point at hidden controls.

## Running a search

1. Type a phrase into the **"Describe what you are looking for"** box. Natural language works well — try *"screen time on weekends"*, *"anxiety symptoms"*, or just an acronym like *"BMI"*. Press **Enter** or click **Search Variables** to run.

2. Use the **Similarity Threshold** slider to control how strictly results must match your query. The default (0.3) is a reasonable starting point. Increase it to narrow results to close matches; decrease it to cast a wider net.

3. Choose a **corpus** from the model selector below the search button:

    | Option | Corpus | Variables (7.0) |
    |---|---|---|
    | ChatBot Pro (no imaging) | Core dictionary only | ~37,000 |
    | ChatBot Pro Max Ultra (all) | Core + imaging variables | ~94,000 |

    Use *ChatBot Pro* for most queries. Switch to *Max Ultra* only when you are specifically looking for imaging-related variables.

While the search runs, the button label changes to "Searching…" and a brief dialog confirms the query is in progress. On narrow viewports (≤ 768 px), the moment you run a search both sidebars collapse and the results table expands to a full-screen view so it fills the display; each sidebar's edge arrow toggles it back open, and the full-screen view's *Close* button (top-right) returns to the normal layout.

## Reading the results table

Results appear in the **Explore** tab, ranked by similarity score (highest first). The desktop view shows a curated 8-column set:

| Column | What it shows |
|---|---|
| **Score** | Cosine similarity to your query (0–1). Higher means a closer match. |
| **Variable Name** | Short machine-readable identifier (e.g., `cbcl_scr_syn_anxdep_t`). |
| **Description** | Human-readable label from the ABCD data dictionary. |
| **Domain** | Thematic grouping (e.g., *Mental Health*, *Physical Health*). |
| **Sub-Domain** | Finer-grained category within a domain. |
| **Source** | The instrument or module the variable belongs to. |
| **Type** | Variable type (e.g., `numeric`, `string`). |
| **Type Level** | Sub-classification within the type. |

On mobile (≤ 768 px), the table is automatically reduced to **Variable Name** + **Description**, and both columns shrink and wrap their text to fit the screen width instead of scrolling horizontally.

The table also supports **column-level filtering** (input boxes under each header), a **full-table search** box (top-right of the table), **column resizing**, and **pagination**.

### Row details modal

Click any row to open a modal listing **every column** in the dictionary for that variable (the curated 8 first, then everything else). This is the only way to see fields like `notes`, `value_range`, or instrument-specific metadata that aren't part of the default table view.

The selection checkbox at the start of each row is for the *Delete Selected Rows* action (see below) and does **not** open the modal.

## Refining results

The **Refine Results** panel on the right lets you narrow the result set after a search.

### Filters

Three searchable multi-select dropdowns let you restrict results by **Source**, **Domain**, and **Variable Type**. Leaving a filter empty means "no restriction on this dimension"; selecting one or more values keeps only matching rows. Click the *×* next to a chip to remove that value, or open the dropdown to add more. Filters compose with the similarity search and with each other; running a new search does **not** clear them.

### Deleting rows

Use each row's selection checkbox to mark it (multi-select supported). Press **Delete Selected Rows** to remove them from the current result set. Deletions persist until you run a new search.

### Downloading results

Click **Download as CSV** to export the **currently visible columns** as `search_results.csv`. The CSV reflects whatever view is active — desktop's curated 8 columns by default, or the mobile 2-column view on small screens.

### Copy variable names

Click **Copy Variable Names** to copy the variable names of your current results to the clipboard, **one per line** — ready to paste into an R script, a spreadsheet, or the NBDCtools snippet below. It copies the names of *all* matching rows (respecting any active column filters and full-table search), not just the current page. The button briefly confirms how many names were copied.

## Loading results into R

Switch to the **Additional Info** tab for a ready-to-paste R snippet that loads your downloaded CSV and builds an ABCD dataset using [NBDCtools](https://github.com/nbdc-datahub/ABCDtools):

```r
library(readr)
library(NBDCtools)

search_results <- read_csv("search_results.csv")
data <- create_dataset(
  study        = "abcd",
  data_dir     = "<Path To Your Raw Data>",
  vars         = search_results$name
)
```
