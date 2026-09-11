/*==================================================================
 PROYECTO:  IPM/MPM - QNG - Guinea Ecuatorial
 SCRIPT:    04_exportar_figuras.do
 --------------------------------------------------------------------
 PROPÓSITO
   Generar las figuras/cuadros de salida del pipeline. El script está
   dividido en DOS SECCIONES, según el tipo de salida que produce cada
   bloque:

     PARTE 1 (EXPORTACIONES A EXCEL) -> todo lo que termina en un
     archivo .xlsx, vía `export excel` o `putexcel`. Contiene
     ÚNICAMENTE las 4 pestañas seleccionadas para esta versión:
       1) "Dep by Quintile"           -> privaciones por quintil de gasto
       2) "Headcount"                 -> headcount (H) por área/provincia
       3) "Radar Dep"                 -> headcount no censurado por indicador (urbano/rural)
       4) "Monetary and deprivations" -> pobreza monetaria por estado de privación

     PARTE 2 (FIGURAS NATIVAS DE STATA) -> gráficos dibujados
     directamente por Stata (`twoway`, `coefplot`, `pvenn2`, mapas),
     exportados con `graph export`. Esta sección TODAVÍA NO fue
     recortada (pendiente de definir qué figuras se conservan aquí).

 OUTPUTS GENERADOS
   - "${gdExcel}/$MPM/$language/${MPM}_QNG.xlsx" con las 4 hojas
     listadas arriba. La carpeta la crea 00_maestro.do (paso 4).
==================================================================*/

* OJO: aquí NO va `clear all`.
*   00_maestro.do llama a este archivo con `include`, que comparte la
*   misma sesión de Stata. Y `clear all` incluye un `macro drop _all`,
*   es decir, borra TODOS los globals: $gdExcel, $gdStata, $MPM,
*   $language... Sin ellos, $excel_export queda en "///_QNG.xlsx" y el
*   primer `use` busca "/Data Clean /DataDeprivations.dta", que no
*   existe: nada llega al Excel.
*   Si en algún momento hace falta vaciar la memoria, usar `clear`
*   (borra los datos pero conserva los globals), nunca `clear all`.


/*==================================================================
 ================  PARTE 1: EXPORTACIONES A EXCEL  ================
==================================================================*/

* Ruta del Excel de salida, reutilizada en las 4 secciones de abajo.
global excel_export "${gdExcel}/${MPM}/${language}/${MPM}_QNG.xlsx"

* Valor monetario a mostrar en etiquetas (formato de decimales según
* idioma: punto en inglés, coma en español), usado en la sección 3
* (Radar Dep).
if "$language"=="ENG"{
    if "$MPM"== "MPM"{
    global monval "3.00"
    global MPMPIP 300
    }
    else {
    global monval "8.30"
    global MPMPIP 830
    }
}
else if "$language"=="SPA"{
    if "$MPM"== "MPM"{
    global monval "3,00"
    global MPMPIP 300
    }
    else {
    global monval "8,30"
    global MPMPIP 830
    }
}


/*------------------------------------------------------------------
 1: Privaciones por quintil de gasto (hoja "Dep by Quintile")
------------------------------------------------------------------*/
preserve
    use "${gdStata}/Data Clean $MPM/DataDeprivations${MPM}.dta",clear
    * Número total de privaciones (sin ponderar por peso del indicador)
    * que acumula cada hogar, sumando las 6 dummies de privación.
    egen deps = rowtotal(dep_educ_com dep_educ_enr dep_infra_elec dep_infra_imps dep_infra_impw dep_poor1)
    * Para cada umbral 1 a 6, indicador de "el hogar acumula AL MENOS
    * esa cantidad de privaciones" (deps_1 = al menos 1, ..., deps_6 =
    * las 6 a la vez). Es una forma sencilla de ver la distribución de
    * la "carga" de privaciones sin pasar por el M0 ponderado.
    foreach x of numlist 1/6{
        gen deps_`x' = (deps>=`x')

    }

    collapse (mean) deps_* [aw= weight_hh], by(quintile)

    foreach x of numlist 1/6{
        replace deps_`x'= deps_`x'*100
        replace deps_`x' = round(deps_`x', 0.1)

    }
    if "$language" == "ENG" {
    label var deps_1 "1 Deprivation"
    foreach x of numlist 2/6{
    label var deps_`x' "`x' Deprivations"
    }
    label drop quintile
    gen Q = "Quintile"
    }

    else if "$language" == "SPA" {
    label var deps_1 "1 Privación"
    foreach x of numlist 2/6{
    label var deps_`x' "`x' Privaciones"
    }
    label drop quintile
    gen Q = "Quintil"
    }
    order Q
    export excel "$excel_export", sheet("Dep by Quintile", modify) firstrow(varlabels)
restore


/*------------------------------------------------------------------
 2: Cuadro del headcount de pobreza (H) por área/provincia (hoja "Headcount")
------------------------------------------------------------------*/
preserve
    use "${gdStata}/${MPM}_results.dta",clear
    * `subg_name` ya viene armado desde 03_calculo_mpm_mpitb.do (diccionario
    * loa-subg-subg_name a partir de las etiquetas de area/prov/cities), no
    * hace falta reconstruirlo a mano aquí.
    replace subg = 0 if loa=="nat"

    drop if loa=="area"
    gen orden=.
        replace orden=1 if loa=="nat"
        replace orden=2 if loa=="cities"
        replace orden=3 if loa=="prov"

    keep subg_name b measure loa subg orden
    keep  if measure=="H"
        replace b = b*100

    sort orden subg
    drop orden subg

    * Se copian los valores a una matriz de Stata (en vez de exportar
    * directamente el dataset) porque `putexcel ... matrix()` permite
    * controlar mejor el formato numérico y las etiquetas de fila/columna
    * en el Excel de salida.
    matrix M = J(11, 1, .)

    local vars b
    forvalues i = 1/11 {
        local j = 1
        foreach var of local vars {
            matrix M[`i', `j'] = `var'[`i']
            local j = `j' + 1
        }
    }

     * Etiquetas según idioma
    if "$language" == "SPA" {
        matrix rownames M = "Nacional" "Malabo" "Resto urbano" "Rural" "Annobón" "Bioko Norte" "Bioko Sur" "Centro Sur" "Kié-Ntem" "Litoral" "Wele Nzas"
    matrix colnames M = "Headcount MPM"
    }
    else if "$language" == "ENG" {
        matrix rownames M = "National" "Malabo" "Other urban" "Rural" "Annobón" "Bioko Norte" "Bioko Sur" "Centro Sur" "Kié-Ntem" "Litoral" "Wele Nzas"
        matrix colnames M = "Headcount MPM"
    }

    matrix list M

    * Exportar a excel (interno)
    putexcel set "$excel_export", sheet("Headcount") modify
    putexcel B2 = matrix(M), names  nformat(number_d2)
restore


/*------------------------------------------------------------------
 3: "Radar" del headcount NO censurado por indicador, urbano/rural
    (hoja "Radar Dep")
------------------------------------------------------------------*/
preserve
    use "${gdStata}/${MPM}_results.dta",clear
    keep if inlist(loa,"cities","nat")
        replace subg = 0 if loa=="nat"
        label def cities 1 "Malabo" 2 "Other Urban" 3 "Rural" 0 "National"
        label val subg cities

        keep subg b measure indicator
            replace b= b*100
        keep  if measure=="hd" // headcount NO censurado: % que es privado en
                                // ese indicador, sin importar si es o no pobre
                                // multidimensional en conjunto (a diferencia
                                // de "hdk", que sí está censurado a los pobres)

        reshape wide b, i(subg) j(indicator) string
        rename b* *
        drop measure


        matrix M = J(4, 6, .)

        local vars poor1 e_com e_enr i_elec i_imps i_impw
        forvalues i = 1/4 {
            local j = 1
            foreach var of local vars {
                matrix M[`i', `j'] = `var'[`i']
                local j = `j' + 1
            }
        }

            * Etiquetas según idioma
            if "$language" == "SPA" {
                matrix rownames M = "Nacional" "Malabo" "Resto urbano" "Rural"
                matrix colnames M = "Monetaria (USD $monval PPA 2021)" "Logro educativo" "Matrícula escolar"  "Electricidad" "Saneamiento" "Agua"
            }
            else if "$language" == "ENG" {
                matrix rownames M = "National" "Malabo" "Other urban" "Rural"
                matrix colnames M = "Monetary ($monval USD PPP 2021)" "Educational attainment" "Educational enrollment" "Electricity" "Sanitation" "Water"
            }

        matrix list M

        * Exportar a excel (interno)
        putexcel set "$excel_export", sheet("Radar Dep", replace) modify
        putexcel B2 = matrix(M), names  nformat(number_d2)
restore


/*------------------------------------------------------------------
 4: Tasa de pobreza monetaria por estado de privación no monetaria
    (hoja "Monetary and deprivations")
------------------------------------------------------------------*/

    use "${gdStata}/Data Clean $MPM/DataDeprivations${MPM}.dta",clear


    duplicates drop hhid, force

    * Para cada indicador no monetario, calculamos la tasa de pobreza
    * monetaria (monetary1) separada entre hogares privados (dep=1) y
    * no privados (dep=0) en ESE indicador. Esto permite ver, por
    * ejemplo, si los hogares sin acceso a electricidad son también más
    * propensos a ser monetariamente pobres. Cada resultado parcial se
    * guarda en un `tempfile` y se concatena al final con `append`.
    foreach var in "dep_educ_com" "dep_educ_enr" "dep_infra_elec" "dep_infra_imps" "dep_infra_impw"{
    preserve
        collapse (mean) monetary1 [aw= weight_hh*hhsize], by(`var')
        gen var = "`var'"
        rename `var' dep

        tempfile depmon_`var'
        save `depmon_`var'', replace
    restore

    }

    use `depmon_dep_educ_com', clear
    foreach var in "dep_educ_enr" "dep_infra_elec" "dep_infra_imps" "dep_infra_impw"{
        append using `depmon_`var''
    }


    replace monetary1= monetary1*100
    reshape wide monetary1, i(var) j(dep)
        rename monetary1* monetary*


        matrix M = J(5, 2, .)

        local vars monetary0 monetary1
        forvalues i = 1/5 {
            local j = 1
            foreach var of local vars {
                matrix M[`i', `j'] = `var'[`i']
                local j = `j' + 1
            }
        }


        * Etiquetas según idioma
        if "$language" == "SPA" {
            matrix rownames M = "Logro educativo" "Matrícula escolar"  "Electricidad" "Saneamiento" "Agua"
            matrix colnames M = "No privado" "Privado"
        }
        else if "$language" == "ENG" {
            matrix rownames M = "Educational attainment" "Educational enrollment" "Electricity" "Sanitation" "Water"
            matrix colnames M = "No deprived" "Deprived"
        }

        matrix list M

        * Exportar a excel (interno)
        putexcel set "$excel_export", sheet("Monetary and deprivations", replace) modify
        putexcel B2 = matrix(M), names  nformat(number_d2)


display "Fin de 04_exportar_figuras.do: Parte 1 (4 hojas Excel) completada."
