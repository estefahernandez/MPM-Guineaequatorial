/*==================================================================
 PROYECTO:      Medida de Pobreza Multidimensional (IPM / MPM)
                Guinea Ecuatorial (ENH2-2023)
 SCRIPT:        06_Sample_dataraw.do
 AUTOR ORIGINAL: Banco Mundial, proyecto GNQ-PA
==================================================================*/


* Cargar datos
// use "$gdData/v1.0_s/Households.dta", clear
use "$gdData/CleanDB_Household_POV.dta", clear

* Sacar muestra aleatoria (ej: 20% del total)
set seed 12345                  // para reproducibilidad
sample 10                       // porcentaje que quieres

* Quedarnos solo con el identificador de los hogares muestreados
keep interview__key

tempfile hh_sample
save `hh_sample'

* Cargar la base de individuos y quedarnos solo con quienes pertenecen
* a un hogar muestreado
// use "$gdData/v1.0_s/Individuals.dta", clear
use "$gdData/CleanDB_Individual_POV.dta", clear

merge m:1 interview__key using `hh_sample'
keep if _merge == 3
drop _merge

// save "$gdData/sample_data.dta", replace
save "$gdData/Individuals_data.dta", replace

