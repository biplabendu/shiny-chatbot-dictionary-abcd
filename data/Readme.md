# Obtaining the data dictionary

#### 1. Download the ABCD 6.0 dd using R

```r
NBDCtools::get_dd_abcd(release = "6.0") |> write.csv("path/to/your/directory/dd-abcd-6_0.csv", row.names = FALSE)
```

#### 2. Select only relevant columns and add a logical `substudy` column (TRUE if substudy, FALSE if core).

<img width="600" height="600" alt="image" src="https://github.com/user-attachments/assets/510add5f-7e14-4e10-a993-1dc0ce294574" />

`dd-abcd-6_0_minimal.csv` was created from the full csv file using `pandas`:

```python
import pandas as pd
abcd_df = pd.read_csv('dd-abcd-6_0.csv')

# using only subset of columns that are relevant
abcd_min_df = abcd_df[["source", 'domain', 'sub_domain', 'table_name', 'table_label', 'name', 'label',"unit", "type_var", "type_data", "type_level"]]

# creating a new columns to indicate if the element is part of `substudy`
substudy_domains = ['COVID-19', 'Endocannabinoid', 'Hurricane Irma', 'MR Spectroscopy', 'Social Development']
abcd_min_df["substudy"] = (
    abcd_min_df["domain"]
    .isin(substudy_domains)
    .where(abcd_min_df["domain"].notna())
    .astype("boolean")
)

abcd_min_df.to_csv("dd-abcd-6.0_minimal.csv", index=False, na_rep="NA")
```

#### 3. Removing rows that are related to Imaging questions

Around 70% of the questions are related to imaging, and for testing purpose we created a subset that doesn't have these questions. It is saved in `dd-abcd-6.0_minimal_noimag.csv`, and it was created from `dd-abcd-6.0_minimal.csv` suing the following filter:


```python
import pandas as pd
abcd_df = pd.read_csv('dd-abcd-6_0_minimal.csv')
# filtering domains
rcdict_small = rcdict[rcdict["domain"] != 'Imaging']
rcdict_small.to_csv("dd-abcd-6.0_minimal_noimag.csv", index=False, na_rep="NA")
```


