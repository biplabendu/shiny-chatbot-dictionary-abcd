# Using the app

[TOC]

The app is divided into three main areas: a **left sidebar** for entering your search, a **main results table** for exploring matches, and a **right sidebar** for refining and exporting what you find.

## Running a search

1. Type a phrase into the **"Describe what you are looking for"** box. Natural language works well — try *"screen time on weekends"*, *"anxiety symptoms"*, or just an acronym like *"BMI"*. Press **Enter** or click **Search Variables** to run.

2. Use the **Similarity Threshold** slider to control how strictly results must match your query. The default (0.3) is a reasonable starting point. Increase it to narrow results to close matches; decrease it to cast a wider net.

3. Choose a **corpus** from the model selector below the search button:

    | Option | Corpus | Variables |
    |---|---|---|
    | ChatBot Pro (no imaging) | Core dictionary only | ~26,000 |
    | ChatBot Pro Max Ultra (all) | Core + imaging variables | ~83,000 |

    Use *ChatBot Pro* for most queries. Switch to *Max Ultra* only when you are specifically looking for imaging-related variables.

While the search runs, the button label changes to "Searching…" and a brief dialog confirms the query is in progress.

## Reading the results table

Results appear in the **Explore** tab, ranked by similarity score (highest first). Key columns:

| Column | What it shows |
|---|---|
| **Score** | Cosine similarity to your query (0–1). Higher means a closer match. |
| **Variable Name** | Short machine-readable identifier (e.g., `cbcl_scr_syn_anxdep_t`). |
| **Description** | Human-readable label from the ABCD data dictionary. |
| **Source** | The instrument or module the variable belongs to. |
| **Domain** | Thematic grouping (e.g., *Mental Health*, *Physical Health*). |

The table also supports **column-level filtering** (input boxes under each header), a **full-table search** box (top-right of the table), **column resizing**, and **pagination**.

## Refining results

The **Refine Results** panel on the right lets you narrow the result set after a search.

### Source and Domain filters

Uncheck any **Source** or **Domain** entries to hide those rows. Use **Select All / Deselect All** to toggle an entire group at once. These filters apply on top of the search — running a new search resets them.

### Deleting rows

Click any row to select it (hold Shift to range-select, Ctrl/Cmd to add individual rows). Press **Delete Selected Rows** to remove them from the current result set. Deletions persist until you run a new search.

### Downloading results

Click **Download as CSV** to export the currently visible columns as `search_results.csv`. If the **Show only name column** view is active, only the `name` column is exported.

### Show only name column

The **Show only name column** button hides all columns except **Variable Name**, giving a compact list useful for copying a variable selection. Click it again to restore all columns.

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
