// Data cleaning pipeline for the simple linear regression with a
// quantitative regressor (medical spending)
//
// NOTE: The paths to the data are directory relative, cd to the
// directory first in stata, then run the do file.
//
// Input:  data/sl_quantitative_raw.dta    (IPUMS CPS ASEC, 2019-2026)
// Output: data/sl_quantitative_clean.dta  (one row per man, first appearance)
//
// IPUMS codes used below:
//   SEX      1 = male
//   CLASSWLY 0 = NIU, 10-14 = self-employed, 20-28 = wage/salary,
//            26 = armed forces, 29 = unpaid family worker
//   NUMEMPS  0 = NIU, 1 = one, 2 = two, 3 = three or more
//   GRPOWNLY 0 = NIU, 1 = no, 2 = yes
//   MOOP     family medical out-of-pocket spending (dollars)
//   HIPVAL   family health insurance premium payments (dollars)
//   CPI99    CPI-U adjustment factor to 1999 dollars

clear all

log using "logs/sl_quantitative.log", replace

local raw   "data/sl_quantitative_raw.dta"
local clean "data/sl_quantitative_clean.dta"

use "`raw'", clear

*-------------------------------------------------------------------------------
* 1. Restrict the sample
*-------------------------------------------------------------------------------
// Men
keep if sex == 1

// Aged 26-64
keep if inrange(age, 26, 64)

// Wage & salary workers last year (not self-employed, not armed forces).
keep if inrange(classwly, 20, 28) & classwly != 26

// Employed at some point last year
keep if numemps != 0

// Policyholders of their own employer coverage
keep if grpownly == 2

// Keep each person's first appearance (people can be in two consecutive ASECs)
drop if cpsidp == 0
isid cpsidp year
bysort cpsidp (year): keep if _n == 1
isid cpsidp

*-------------------------------------------------------------------------------
* 2. Create y
*-------------------------------------------------------------------------------
// JobChange: 1 if two or more employers, 0 if exactly one
gen byte jobchange = .
replace jobchange = 1 if numemps >= 2 & numemps < .
replace jobchange = 0 if numemps == 1
label variable jobchange "Two or more employers last year"

*-------------------------------------------------------------------------------
* 3. Create x
*-------------------------------------------------------------------------------
// Ensure that MOOP includes premiums (measured by HIPVAL) to adjust for
count if moop < hipval
assert r(N) == 0

// Medical spending net of premiums, in constant 1999 dollars
gen double medspend = (moop - hipval) * cpi99
label variable medspend "Family non-premium medical OOP spending (1999 $)"

// Check the distribution and zeroes for skewness
summarize medspend, detail
count if medspend == 0
tabstat medspend, statistics(p90 p95 p99 max) by(year)

// The top of the distribution is extreme (max is several hundred times the
// median), so cap at the 99th percentile.
_pctile medspend, percentiles(99)
local cap = r(r1)
display "99th percentile cap: " %9.2f `cap'
count if medspend > `cap'

gen double medspend_cap = min(medspend, `cap')
label variable medspend_cap "Medical spending, capped at p99 (1999 $)"

// Version 1.a: thousands of dollars, uncapped
gen double medspend_k = medspend / 1000
label variable medspend_k "Medical spending (thousands of 1999 $)"

// Version 1.b: thousands of dollars, capped
gen double medspend_k_cap = medspend_cap / 1000
label variable medspend_k_cap "Medical spending, capped at p99 (thousands of 1999 $)"

// Version 2: log of one plus spending. The log already compresses the right
// tail, so it is built from the uncapped dollars.
gen double ln_medspend = ln(1 + medspend)
label variable ln_medspend "Log of one plus medical spending (1999 $)"

// Summarize results for each regressor
summarize medspend_k medspend_k_cap ln_medspend, detail

// Summarize results for each regressor, ordered by jobchange
tabstat medspend_k medspend_k_cap ln_medspend, statistics(n mean sd) by(jobchange)

// Convert existing variables to ideal types before storing
compress
save "`clean'", replace

log close
