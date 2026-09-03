/*==================================================================
 PROYECTO:  IPM/MPM - QNG - Guinea Ecuatorial
 SCRIPT:    03_calculo_mpm.do  (implementación MANUAL, sin mpitb)
 --------------------------------------------------------------------
 PROPÓSITO
   Calcula manualmente el Índice de Pobreza Multidimensional (IPM)
   usando el método Alkire-Foster (2011) SIN el paquete externo
   `mpitb`. Replica exactamente los resultados de H, A y M0 producidos
   por el script oficial ($gdDo/03_calculo_mpm_mpitb.do) para las
   mismas dimensiones, pesos y umbral de corte.

 MÉTODO ALKIRE-FOSTER — IMPLEMENTACIÓN PASO A PASO
   1. Pesos iguales entre dimensiones (1/3 cada una) e iguales dentro
      de cada dimensión ("equal weighting"):
        w_e_com  = 1/2 * 1/3 = 1/6
        w_e_enr  = 1/2 * 1/3 = 1/6
        w_i_elec = 1/3 * 1/3 = 1/9
        w_i_imps = 1/3 * 1/3 = 1/9
        w_i_impw = 1/3 * 1/3 = 1/9
        w_poor1  = 1/1 * 1/3 = 1/3
        Suma total = 1/6+1/6+1/9+1/9+1/9+1/3 = 1  ✓

   2. Puntaje de privación ponderado por hogar:
        c_h = Σ w_j * d_hj   (suma sobre los 6 indicadores j)

   3. Identificación de pobreza multidimensional (k = 33% = 1/3):
        poor_multi_h = 1  si  c_h >= 1/3

   4. Puntaje censurado:
        c_censored_h = c_h * poor_multi_h

   5. Medidas de resumen con diseño muestral complejo (svy).
      Las TRES medidas agregadas del método son medias ponderadas; lo
      único que cambia entre ellas es QUÉ se promedia y SOBRE QUIÉN:

        H  = media de poor_multi  sobre TODA la población
             (incidencia: % de personas pobres multidimensionales)

        A  = media de c_h  SOLO ENTRE LOS POBRES
             (intensidad: qué proporción de las privaciones ponderadas
              posibles sufre, en promedio, una persona pobre)

        M0 = media de c_censored  sobre TODA la población
             (headcount ajustado, "el MPM")

      Escritas como sumas ponderadas (w_i = ponderador poblacional,
      p_i = poor_multi, c_i = puntaje de privación):

        H  = Σ w_i·p_i     / Σ w_i
        M0 = Σ w_i·c_i·p_i / Σ w_i
        A  = Σ w_i·c_i·p_i / Σ w_i·p_i   <- MISMO numerador que M0,
                                            distinto denominador

      Al dividir M0 entre H se cancela Σ w_i y queda exactamente A. De
      ahí la identidad fundamental del método:   M0 = H * A

      Consecuencia práctica: A es la única de las tres que NO se
      promedia sobre toda la población, y por eso se estima con
      subpop(if poor_multi==1). (Entre los pobres c_h == c_censored,
      así que promediar cualquiera de las dos variables da lo mismo.)

      Ref.: Suppa (2023), "mpitb: A toolbox for multidimensional
      poverty indices", Stata Journal 23(3), sección 2, p. 627.

==================================================================*/

*------------------------------------------------------------------
* 0. CAPTURA PREVIA DE RESULTADOS mpitb PARA VALIDACIÓN
*    Si ya existe el archivo de resultados (generado por
*    03_calculo_mpm_mpitb.do), se guarda en un tempfile ANTES de
*    que este script lo sobreescriba, para poder comparar al final.
*------------------------------------------------------------------
tempfile mpitb_backup
local mpitb_exists 0
capture confirm file "${gdStata}/${MPM}_results.dta"
if _rc == 0 {
    use "${gdStata}/${MPM}_results.dta", clear
    keep if inlist(measure, "H", "M0") & k == 33
    * Normalizar subg a string para el merge posterior
    capture confirm string variable subg
    if _rc != 0 {
        tostring subg, replace force
        replace subg = "" if subg == "."
    }
    save `mpitb_backup'
    local mpitb_exists 1
}

*------------------------------------------------------------------
* 1. CARGAR DATOS Y PREPARAR VARIABLES (idéntico a 03_calculo_mpm_mpitb.do)
*------------------------------------------------------------------
use "${gdStata}/Data Clean $MPM/DataDeprivations${MPM}.dta", clear

keep hhid provincia cod_provincia cod_CV_CP q1_03_edad hhsize weight_hh      ///
     pcexp_ppp educat7 asistencia_escolar electricity imp_san_rec           ///
     imp_wat_rec dep_educ_com dep_educ_enr dep_infra_elec                  ///
     dep_infra_imps dep_infra_impw dep_poor1 quintile cities

rename dep_* *      // dep_educ_com -> educ_com, dep_infra_elec -> infra_elec, etc.
rename infra_* i_*  // infra_elec -> i_elec, infra_imps -> i_imps, infra_impw -> i_impw
rename educ_* e_*   // educ_com -> e_com, educ_enr -> e_enr

duplicates drop hhid, force   // 1 fila por hogar (requisito del método AF)

* Ponderador expandido a nivel de personas (peso_hogar × tamaño_hogar)
gen hhweight = weight_hh * hhsize

* Variable de estratificación (provincia × área urbano/rural)
egen strata = group(cod_provincia cod_CV_CP)

* Declarar diseño muestral complejo
svyset hhid [iw=hhweight], clear strata(strata)

* Renombrar variables geográficas de desagregación
rename (cod_CV_CP cod_provincia) (area prov)

*------------------------------------------------------------------
* 2. PUNTAJE DE PRIVACIÓN ALKIRE-FOSTER Y CLASIFICACIÓN POBRE/NO POBRE
*------------------------------------------------------------------
* c_equal: puntaje de privación ponderado (mismo nombre que mpitb)
gen c_equal = (1/3)*( (1/2)*e_com + (1/2)*e_enr ) + ///
              (1/3)*( (1/3)*i_elec + (1/3)*i_imps + (1/3)*i_impw ) + ///
              (1/3)*(1)*poor1
label var c_equal "Deprivation score (equal weights)"

* Identificación de pobreza multidimensional: k = 33% (=33/100) (= 1/3)
gen poor_multi = (c_equal >= 1/3)
label var poor_multi "Multidimensional poor (k=33)"

* Puntaje censurado: c_h si pobre, 0 si no pobre
* Media ponderada de este puntaje = M0 = H * A
gen c_censored = c_equal * poor_multi
label var c_censored "Censored deprivation score"

*------------------------------------------------------------------
* 3. ESTIMACIÓN DE H, A y M0 CON DISEÑO MUESTRAL COMPLEJO
*    Se usa svy: mean (comando base de Stata, sin ado externos).
*    Para desagregaciones, se usa subpop() —no if— para preservar
*    la estimación correcta de la varianza con el diseño complejo.
*    En cada nivel de agregación hacen falta DOS llamadas a svy: mean:
*      1a) mean poor_multi c_censored            -> H y M0
*      1b) mean c_equal, subpop(poor_multi==1)   -> A
*------------------------------------------------------------------

* Detectar si las variables de desagregación son string o numéricas,
* para construir correctamente la condición de subpop().
local area_type:  type area
local prov_type:  type prov
local cities_type: type cities

* Abrir postfile para almacenar resultados
tempname memhold
tempfile results_manual
postfile `memhold' str10 measure str10 loa str50 subg int k       ///
    double b double se using `results_manual', replace

*---- Nacional ----
* H y M0 salen de la MISMA llamada: ambas son medias sobre toda la población.
quietly svy: mean poor_multi c_censored
matrix B = e(b)
matrix V = e(V)
post `memhold' ("H")  ("nat") ("") (33) (B[1,1]) (sqrt(V[1,1]))
post `memhold' ("M0") ("nat") ("") (33) (B[1,2]) (sqrt(V[2,2]))

* A (intensidad) necesita una llamada aparte, porque se promedia solo
* entre los pobres. subpop() restringe el promedio a poor_multi==1 sin
* recortar la muestra, de modo que el error estándar sigue reflejando
* correctamente el diseño complejo (esto es justo lo que un `if` haría mal).
quietly svy, subpop(if poor_multi==1): mean c_equal
matrix B = e(b)
matrix V = e(V)
post `memhold' ("A")  ("nat") ("") (33) (B[1,1]) (sqrt(V[1,1]))

*---- Por área (urbano / rural) ----
levelsof area, local(areas)
foreach a of local areas {
    * La condición de subpop() se escribe distinto según `area` sea string
    * o numérica. Se arma UNA vez en el local `cond` y se reutiliza para
    * las tres medidas, en vez de repetir el if/else en cada llamada svy.
    if strpos("`area_type'", "str") > 0   local cond `"area == "`a'""'
    else                                  local cond `"area == `a'"'

    * H y M0: medias sobre toda el área
    quietly svy, subpop(if `cond'): mean poor_multi c_censored
    matrix B = e(b)
    matrix V = e(V)
    post `memhold' ("H")  ("area") ("`a'") (33) (B[1,1]) (sqrt(V[1,1]))
    post `memhold' ("M0") ("area") ("`a'") (33) (B[1,2]) (sqrt(V[2,2]))

    * A: media del puntaje entre los pobres DE ESA área
    quietly svy, subpop(if `cond' & poor_multi==1): mean c_equal
    matrix B = e(b)
    matrix V = e(V)
    post `memhold' ("A")  ("area") ("`a'") (33) (B[1,1]) (sqrt(V[1,1]))
}

*---- Por provincia ----
levelsof prov, local(provs)
foreach p of local provs {
    * Misma lógica que en el bucle de áreas (ver comentario arriba)
    if strpos("`prov_type'", "str") > 0   local cond `"prov == "`p'""'
    else                                  local cond `"prov == `p'"'

    * H y M0: medias sobre toda la provincia
    quietly svy, subpop(if `cond'): mean poor_multi c_censored
    matrix B = e(b)
    matrix V = e(V)
    post `memhold' ("H")  ("prov") ("`p'") (33) (B[1,1]) (sqrt(V[1,1]))
    post `memhold' ("M0") ("prov") ("`p'") (33) (B[1,2]) (sqrt(V[2,2]))

    * A: media del puntaje entre los pobres DE ESA provincia
    quietly svy, subpop(if `cond' & poor_multi==1): mean c_equal
    matrix B = e(b)
    matrix V = e(V)
    post `memhold' ("A")  ("prov") ("`p'") (33) (B[1,1]) (sqrt(V[1,1]))
}


postclose `memhold'

*------------------------------------------------------------------
* 4. GUARDAR RESULTADOS AGREGADOS
*    Se guarda en el mismo path que produce 03_calculo_mpm_mpitb.do
*    para que 04_exportar_figuras.do pueda usar cualquiera de los
*    dos scripts de forma intercambiable.
*------------------------------------------------------------------
use `results_manual', clear
sort measure loa subg
save "${gdStata}/${MPM}_results.dta", replace

* Inspección rápida de resultados nacionales
di ""
di "=== H, A y M0 nacionales (k=33%) — implementación manual ==="
list measure b se if loa == "nat", noob

*------------------------------------------------------------------
* 5. GUARDAR MICRODATOS CON c_equal Y poor_multi
*    (mismo formato que produce mpitb; compatible con
*     04_exportar_figuras.do)
*------------------------------------------------------------------
use "${gdStata}/Data Clean $MPM/DataDeprivations${MPM}.dta", clear

keep hhid provincia cod_provincia cod_CV_CP hhsize weight_hh              ///
     electricity imp_san_rec imp_wat_rec dep_educ_com                     ///
     dep_educ_enr dep_infra_elec dep_infra_imps dep_infra_impw dep_poor1  ///
     quintile cities pcexp_ppp educat7 asistencia_escolar

rename dep_* *
rename infra_* i_*
rename educ_* e_*
duplicates drop hhid, force

gen hhweight = weight_hh * hhsize
egen strata   = group(cod_provincia cod_CV_CP)
rename (cod_CV_CP cod_provincia) (area prov)

gen c_equal   = (1/6)*e_com + (1/6)*e_enr +                     ///
                (1/9)*i_elec + (1/9)*i_imps + (1/9)*i_impw +    ///
                (1/3)*poor1
gen poor_multi = (c_equal >= 1/3)
label var c_equal    "Deprivation score (equal weights)"
label var poor_multi "Multidimensional poor (k=33)"

save "${gdStata}/${MPM}_results_microdata.dta", replace

*------------------------------------------------------------------
* 6. VALIDACIÓN: COMPARAR CONTRA LOS RESULTADOS OFICIALES DE mpitb
*    Usa el backup capturado en la sección 0 (antes de sobreescribir).
*    Se comparan H y M0 en todos los niveles de agregación.
*------------------------------------------------------------------
if `mpitb_exists' == 1 {

    di ""
    di "=== VALIDACIÓN: manual (03_calculo_mpm.do) vs mpitb (03_calculo_mpm_mpitb.do) ==="

    * Cargar resultados manuales recién guardados
    use "${gdStata}/${MPM}_results.dta", clear
    keep if inlist(measure, "H", "M0")
    rename b  b_manual
    rename se se_manual
    tempfile manual_vals
    save `manual_vals'

    * Cargar el backup de mpitb y fusionar
    use `mpitb_backup', clear
    merge 1:1 measure loa subg k using `manual_vals', nogenerate

    * Diferencia absoluta entre estimaciones puntuales
    gen diff_b = abs(b - b_manual)

    * Umbral de tolerancia: diferencias < 1e-6 se consideran equivalentes
    gen flag = (diff_b > 1e-6) & !missing(diff_b)

    qui count if flag == 1
    if r(N) == 0 {
        di as result "VALIDACIÓN EXITOSA: H y M0 son idénticos en todos los " ///
                     "niveles de agregación (diferencia < 1e-6)."
    }
    else {
        di as error "ATENCIÓN: `r(N)' combinaciones con diferencias > 1e-6:"
        list measure loa subg b b_manual diff_b if flag == 1, noob
    }
}
else {
    di as text "(Validación omitida: ejecute primero 03_calculo_mpm_mpitb.do " ///
               "y luego vuelva a correr este script para activar la comparación.)"
}
