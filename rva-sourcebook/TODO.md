# TODO.md — punch list

## Task Tracking - 
**Always check TODO.md** before starting work - **Update TODO.md** as tasks are completed (`[x]`), started (`[~]`), or skipped (`[-]`) - Keep TODO.md as the single source of truth for project status

What's left to finish the report. Start every session here. See [LOG.md](LOG.md) for the history behind any line and [METHODOLOGY.md](METHODOLOGY.md) for the data/scope rules that bound the work.

## Data scripts still missing

- [x] `r/acs_stock.R` — housing stock (B25001, B25002/04, B25024, B25034-36, B25041/42): units, occupancy/vacancy, structure type, year built, bedrooms.
- [x] `r/fmr.R` — HUD FY2026 FMR and SAFMR by locality/zip. Files already staged under `data/raw/`.
- [x] `r/oews.R` — OEWS wage affordability, Richmond MSA, latest (2024) release.
- [x] `r/chas.R` extended — Tables 8, 18C, and 17B added for a fact-sheet renter-shortage/cost-burden infographic (`data/chas_gap.rds`); existing Table 7 output renamed `data/chas_cb.rds`. Ran clean 2026-09-04 after correcting three validation tolerances for CHAS's nearest-5 cell rounding (see LOG.md). The infographic/chart itself is not built yet — this is data only.
- [x] `r/chas.R` extended again (2026-09-10) — Tables 18A, 18B, and 17A added, plus Table 8's owner rows, for `fact-sheet-chas.csv`: combined-tenure, 50%-AMI gap and cost-burden figures, one row per locality, for the 6 non-PUMS-coverage localities (Hanover, Goochland, Powhatan, New Kent, Charles City, Ashland). Reproduces the methodology behind the New Kent print fact sheet — ran clean, New Kent's row matches the artifact exactly. See LOG.md for the negative-`needed_not_built` surprise in 5 of the 6 localities and the resulting fact-sheet framing guidance (lead with `gap_total`, not `needed_not_built`).
- [ ] `r/pums/*` — the PUMS engine. `gaps.qmd` sections 1-2 are now unblocked; `pums_labels.R` and `rva_puma.R` are what remain.
  - [x] `pums_collect.R` — ACS 2020-2024 5-year PUMS pull, VA statewide filtered to `puma_region`. Ran clean 2026-09-09 after fixing the real `return_vacant`/`VACS`-duplicate crash (see LOG.md; the two prior entries' diagnosis was wrong). Re-pulled later the same day with `BDSP` added to the vacant supplement and `RNTP` added to the main call — 49 variables, 48 in the main call, identical 52,150 rows. `data/pums_raw.rds` and `data/pums_wgt.rds` written.
  - [x] `pums_prep.R` amendment (see also the utility-allowance line below) — vacant-for-rent units (`VACS == "1"`, 231 records) now survive into `pums_hh.rds` as a second `record_type` carrying `asking_rent`; group-quarters persons are still dropped. Ran clean 2026-09-09; occupied-household count and the ACS B25003 benchmark are unchanged. `pums_ami.R` gained an occupied-only filter and was re-run (see LOG.md). Amended again 2026-09-09 to carry `bedrooms` on both record types and `contract_rent` on occupied cash renters; every prior figure is unchanged.
  - [x] `pums_ami.R` — six-band AMI banding on HUD FY2026 limits, plus band cross-tabs. Amended 2026-09-09 to add a within-band cost-burden count/share (`cb_estimate_*`, `cb_burdened_share`, `cb_severely_share`) to `pums_ami_bands`, sourced from `pums_hh.rds`'s existing `cb_label`. Households with no cost-burden classification (zero/negative income, no-cash-rent renters) are folded into Not cost-burdened, per Jonathan's call. Ran clean 2026-09-09; 48-row `pums_ami_bands` output and the ACS B25003 benchmark are unchanged.
  - [x] `pums_gap.R` — AMI-banded affordable-and-available rental gap and renter-competition table. Ran clean 2026-09-09, then twice more the same day: once for the bedroom-based rent ceiling and the contract-to-contract rent measure, then once for the gross-rent-on-both-sides measure that ships. `data/pums_gap.rds` (220 rows, geography x basis x band x measure) and `data/pums_gap_occupancy.rds` (60 rows). Regional shortage 23,788 units at or below 30% AMI, 26,520 at or below 50%. Method decision 1 revised once and decision 2 twice; all six recorded in METHODOLOGY.md. **The 80%+ AMI figures are still not plottable** — no threshold-basis or rent-measure change moves them, because the 80% AMI ceiling sits above nearly the whole Richmond rental stock. See the log entry.
  - [ ] `pums_labels.R` — variable-label lookup from the PUMS data dictionary.
  - [ ] `rva_puma.R` — PUMA map and coverage validation against `_common.R`.
  - [x] Utility allowance — settled 2026-09-09. The differential is added to the 231 vacant asking rents rather than subtracted from the ceilings, so the ceilings and every occupied record's real `GRNTP` stay as they are. `pums_prep.R` section 7a builds `asking_rent_gross` from a survey-weighted median gross-minus-contract differential by bedroom count ($82/$96/$156/$237/$324/$330 for 0 to 5-or-more bedrooms), and `pums_gap.R` prices both sides on gross rent. Regional shortage 23,788 at or below 30% AMI, 26,520 at or below 50%. Details in METHODOLOGY.md and the 2026-09-09 log entry.
- [ ] `data-notes.qmd` — four PUMS caveats: the mutually exclusive PUMS race groups against the overlapping ACS ones, 2024-dollar incomes banded against FY2026 HUD limits (both from the 2026-08-31 session), and from `pums_gap.R` — the bedroom-based generic household size behind the rent ceilings, and the imputed gross rent on the vacant side, which adds a bedroom-level utility differential to the asking rent.
- [ ] Consolidated rental assistance (LIHTC piece) — blocked on Jonathan sourcing a LIHTC database file. `r/psh.R` already covers the voucher/public-housing program-mix half.

## MLS pipeline — needs a live run

- [ ] `renv::install("tidygeocoder"); renv::snapshot()`
- [ ] Review `data-out/mls_manual_review.csv` (237 unresolved cross-MLS pairs)
- [ ] Run `Rscript r/mls_geocode.R`
- [ ] Once geocoded, `ownership.qmd`'s "Sales inventory and months of supply" callout still needs an active-listings source — the closed-sales MLS export doesn't carry it.

## Chapter gaps

- [ ] `gaps.qmd` sections 1-2 — data is ready (`data/pums_gap.rds`, `data/pums_gap_occupancy.rds`). Chapter build not started.
- [ ] `ownership.qmd` — "Sales inventory and months of supply" callout, depends on an active-listings source.
- [ ] `rental.qmd` — "Submarket rents and vacancy" callout, needs CoStar submarket-level detail.
- [ ] `burden.qmd` — "Cost burden by race and ethnicity (CHAS Table 9)" callout, not yet built.
- [ ] `r/affordcalc.R`'s ownership assumptions (10% down, 30-year term, 1.0% property tax, \$1,500/year insurance, no PMI) are explicit placeholders — need PHA review before treating as final.

## Not started

- [ ] 9 local summaries (`local-*.qmd`) — currently 28-line stubs.
- [ ] `tracker.qmd` — regional progress tracker.
- [ ] `exec-sum.qmd` — executive summary, derived from `archive/soh-2026/`.

## Final assembly

- [ ] `data-notes.qmd` sweep — trim to what's relevant for public/PHA consumption; move technical/internal notes to `METHODOLOGY.md`.
- [ ] Decide whether the repo gets a LICENSE file before final publish.
- [ ] Full `quarto render` completes with no errors, every page written to `docs/`.
- [ ] PDF output renders and lands in `docs/`.
- [ ] Remove the `noindex` robots meta tag from `_quarto.yml`.
- [ ] `grep -rln "@fig-\|@tbl-\|@sec-" *.qmd` shows no match inside a `labs(caption=)` or a `footnote()` call.
- [ ] Every `#| label: fig-` chunk has a matching `#| fig-alt:` line.
- [ ] `git ls-files data-out/` lists no file matching `mls_*` or `costar_*`.
- [ ] Every headline number in the rendered book traces to a `data/*.rds` file — a final number sweep.
- [ ] README.md status line names the report as final rather than in progress.