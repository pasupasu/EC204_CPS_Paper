// Data cleaning pipeline for the simple linear regression
//
// NOTE: The paths to the data are directory relative, cd to the
// directory first in stata, then run the do file.
//
// Input:  data/simple_linear_data_raw.dta  (IPUMS CPS ASEC, 2019-2026)
// Output: data/simple_linear_data_clean.dta   (one row per linked man, year t -> t+1)
//
// IPUMS codes used below:
//   SEX      1 = male
//   MARST    1 = married, spouse present
//   GRPOWNLY 0 = NIU, 1 = no, 2 = yes
//   GRPDEPLY 1 = no, 2 = yes, 9 = NIU
//   NUMEMPS  0 = NIU, 1 = one, 2 = two, 3 = three or more
//   MISH     1-8 = month in sample

clear all

log using "logs/simple_linear.log", replace

local raw   "data/simple_linear_data_raw.dta"
local clean "data/simple_linear_data_clean.dta"

tempfile year_t1

*-------------------------------------------------------------------------------
* Year t+1 records: outcome side of the link
*-------------------------------------------------------------------------------
use cpsidp year mish age sex race numemps using "`raw'", clear

// Returning rotation groups are in months-in-sample 5-8 in their second ASEC
keep if inrange(mish, 5, 8) & cpsidp != 0

// Shift year back so it lines up with the year t record
replace year = year - 1

rename (mish age sex race numemps) =_t1
save `year_t1'

*-------------------------------------------------------------------------------
* 2. Create x in year t
*-------------------------------------------------------------------------------
use "`raw'", clear

// OwnESI: 1 if GRPOWNLY is yes, 0 if no or not in universe
gen byte ownesi = (grpownly == 2)
label variable ownesi "Own employer-sponsored insurance (year t)"

*-------------------------------------------------------------------------------
* 3. Restrict the year t sample
*-------------------------------------------------------------------------------
// Men
keep if sex == 1

// Married with spouse present in the household
keep if marst == 1

// Aged 25-54
keep if inrange(age, 25, 54)

// Wage & salary workers last year (not self-employed, not armed forces).
keep if inrange(classwly, 20, 28) & classwly != 26

// Exactly one employer last year
keep if numemps == 1

// Drop men covered as a dependent on someone else's employer plan
// and without a plan in their own name
drop if grpdeply == 2 & grpownly != 2

// Incoming rotation groups (first ASEC) with a valid person identifier
keep if inrange(mish, 1, 4) & cpsidp != 0

*-------------------------------------------------------------------------------
* 4. Link to year t+1
*-------------------------------------------------------------------------------
merge 1:1 cpsidp year using `year_t1', keep(match) nogenerate

// Validate the link: same sex and race, age rises by 0-2 years
keep if sex_t1 == sex & race_t1 == race
keep if inrange(age_t1 - age, 0, 2)

// Final check: make sure links are properly implemented
count if mish_t1 == mish + 4
keep if mish_t1 == mish + 4

*-------------------------------------------------------------------------------
* 5. Create y from year t+1
*-------------------------------------------------------------------------------
// JobChange: 1 if two or more employers, 0 if exactly one
gen byte jobchange = .
replace jobchange = 1 if numemps_t1 >= 2 & numemps_t1 < .
replace jobchange = 0 if numemps_t1 == 1
label variable jobchange "Two or more employers in year t+1"

// Men with no employer in year t+1 (NUMEMPS NIU) have no defined outcome
drop if missing(jobchange)

// Scan results
tab year jobchange
tab ownesi jobchange, row

// Convert existing variables to ideal types before storing
compress
save "`clean'", replace

log close
