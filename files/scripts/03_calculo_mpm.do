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

* Se abre la base de datos que se construyo en 01_privaciones_mpm.do
use "${gdStata}/Data Clean $MPM/DataDeprivations${MPM}.dta", clear

* Nos quedamos con las variables necesarias 
keep hhid provincia cod_provincia cod_CV_CP q1_03_edad hhsize weight_hh      ///
     pcexp_ppp educat7 asistencia_escolar electricity imp_san_rec           ///
     imp_wat_rec dep_educ_com dep_educ_enr dep_infra_elec                  ///
     dep_infra_imps dep_infra_impw dep_poor1 quintile cities

* Las variables de insumo para el metodo
rename dep_* *      // dep_educ_com -> educ_com, dep_infra_elec -> infra_elec, etc.
rename infra_* i_*  // infra_elec   -> i_elec, infra_imps -> i_imps, infra_impw -> i_impw
rename educ_* e_*   // educ_com     -> e_com, educ_enr -> e_enr

* Sirve dado que es el identificador
duplicates drop hhid, force   // 1 fila por hogar (requisito del método AF)

* Diseño muestrasl al ser el Ponderador expandido a nivel de personas (peso_hogar × tamaño_hogar)
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

* 1. c_equal: puntaje de privación ponderado (mismo nombre que mpitb)
/* 
    primero la pizza se parte en 3 pedazos iguales (uno por dimensión, Educacion,
    Infraestructura y Monetaria), y después el pedazo de cada dimensión se 
    reparte en partes iguales entre sus indicadores. Al multiplicar los dos 
    niveles salen los pesos finales:

          LA PIZZA COMPLETA = 1
        ┌──────────────┬──────────────┬──────────────┐
        │   EDUCACIÓN  │    INFRA     │  MONETARIA   │
        │      1/3     │     1/3      │     1/3      │
        ├──────┬───────┼────┬────┬────┼──────────────┤
        │e_com │ e_enr │elec│imps│impw│    poor1     │
        │ 1/6  │  1/6  │1/9 │1/9 │1/9 │     1/3      │
        └──────┴───────┴────┴────┴────┴──────────────┘
        2 indicadores   3 indicadores    1 indicador
        1/3 ÷ 2 = 1/6   1/3 ÷ 3 = 1/9   1/3 ÷ 1 = 1/3

    Pesos por indicador (equal weighting): 1/3 por dimensión,
    repartido por igual entre los indicadores de cada dimensión.

    ┌───────────┬─────────────┬────────────────┬────────────┐
    │ Indicador │   Cuenta    │ Peso final w_d │ En decimal │
    ╞═══════════╪═════════════╪════════════════╪════════════╡
    │ e_com     │  1/3 × 1/2  │      1/6       │     0.1667 │
    │ e_enr     │  1/3 × 1/2  │      1/6       │     0.1667 │
    │ i_elec    │  1/3 × 1/3  │      1/9       │     0.1111 │
    │ i_imps    │  1/3 × 1/3  │      1/9       │     0.1111 │
    │ i_impw    │  1/3 × 1/3  │      1/9       │     0.1111 │
    │ poor1     │   1/3 × 1   │      1/3       │     0.3333 │
    ├───────────┼─────────────┼────────────────┼────────────┤
    │ Suma      │      —      │       1        │   1.0000 ✓ │
    └───────────┴─────────────┴────────────────┴────────────┘

    Nota: Fíjate en el (1/3)*(1)*poor1: ese (1) es innecesario aritméticamente, 
    pero está puesto a propósito para que se vea que la dimensión monetaria 
    también se reparte internamente — lo que pasa es que tiene un solo indicador 
    y se lleva el pedazo entero. Un solo indicador pesa el doble que cualquiera 
    de educación y el triple que cualquiera de infraestructura, simplemente 
    por estar solo en su dimensión.

    Ejemplo: un hogar sin electricidad y sin agua, pero no pobre monetario y 
    sin problemas educativos → c_i = (sin electricidad → 1/9) + (Sin agua → 1/9) = 0.222.
*/

gen c_equal = (1/3)*( (1/2)*e_com + (1/2)*e_enr ) + ///
              (1/3)*( (1/3)*i_elec + (1/3)*i_imps + (1/3)*i_impw ) + ///
              (1/3)*(1)*poor1
label var c_equal "Deprivation score (equal weights)"

* 2. Identificación de pobreza multidimensional: k = 33% (= 1/3)
/* 
    El paréntesis es una pregunta de sí/no: Stata evalúa la comparación y escribe 1 
    cuando es verdad y 0 cuando es falsa. Es la forma corta de escribir un if/else, 
    y es equivalente a:

    gen poor_multi = 0
    replace poor_multi = 1 if c_equal >= 1/3

    Este es el segundo corte del método (el "dual cutoff" de Alkire-Foster): el primero 
    fue el umbral $z_d$ de cada indicador, que ya aplicó 01_privaciones; este es el corte 
    transversal $k$, que decide cuánta privación acumulada hace a alguien pobre.
*/

gen poor_multi = (c_equal >= 1/3)
label var poor_multi "Multidimensional poor (k=33)"

* 3. Puntaje censurado: c_h si pobre, 0 si no pobre
/*
    Multiplicar por una variable que solo vale 0 o 1 es un interruptor:

    si el hogar es pobre (poor_multi = 1) → c_censored = c_equal, se conserva su puntaje;
    si no lo es (poor_multi = 0) → c_censored = 0, su puntaje se borra.
    Eso es "censurar": el método ignora deliberadamente las privaciones de quien no cruzó 
    el umbral $k$ → 1/3 = 33%. Un hogar con una sola carencia no entra al índice, aunque esa 
    carencia sea real. Es una decisión normativa del método, no un descuido: el IPM mide 
    privación múltiple.

    NO es:   ¿cuántas carencias tiene?     →  2 de 6
    SÍ es:   ¿cuánto pesan sus carencias?  →  1/6 + 1/9 = 0.278
                                               ↑
                                    esto es lo que se compara con 1/3

   Umbral de corte k = 1/3 = 0.333  ->  pobre si c_h >= 1/3
   ┌────────────────────────────────────┬───────────────┬─────────────────────┐
   │             Carencias              │ Suma de pesos │       ¿Pobre?       │
   ╞════════════════════════════════════╪═══════════════╪═════════════════════╡
   │ Solo poor1                         │ 1/3  = 0.333  │ Sí (¡con una sola!) │
   │ Solo e_com                         │ 1/6  = 0.167  │ No                  │
   │ Solo i_elec                        │ 1/9  = 0.111  │ No                  │
   │ i_imps + i_impw                    │ 2/9  = 0.222  │ No                  │
   │ e_com + i_elec                     │ 5/18 = 0.278  │ No                  │
   │ e_com + e_enr (educación completa) │ 1/3  = 0.333  │ Sí                  │
   │ Las 3 de infraestructura           │ 1/3  = 0.333  │ Sí                  │
   │ poor1 + cualquier otra             │      ≥ 0.444  │ Sí                  │
   └────────────────────────────────────┴───────────────┴─────────────────────┘

    Las dimensiones no se evalúan como bloque —nadie pregunta "¿está privado en educación?"
    pero sí determinan los pesos, y por eso aparecen indirectamente: como cada dimensión 
    vale 1/3, tener toda una dimensión privada siempre da exactamente 0.333 y siempre alcanza 
    el umbral, sean 1, 2 o 3 los indicadores de esa dimensión. Ese es el único sentido en que 
    la dimensión completa "cuenta" como criterio.
*/
* Media ponderada de este puntaje = M0 = H * A
gen c_censored = c_equal * poor_multi
label var c_censored "Censored deprivation score"

/*
    ¿POR QUÉ ESTAS TRES VARIABLES Y NO OTRAS?

    Porque las tres medidas del método son promedios ponderados, y lo único que cambia
    entre ellas es QUÉ se promedia y SOBRE QUIÉN — justo lo que hace la sección 3 del
    script con svy: mean.

    ┌───────────────────┬─────────────────┬───────────────────┬─────────────────────────────────────────────┐
    │      Medida       │ Qué se promedia │    Sobre quién    │                  En Stata                   │
    ╞═══════════════════╪═════════════════╪═══════════════════╪═════════════════════════════════════════════╡
    │ $H$  (incidencia) │ poor_multi      │ toda la población │ svy: mean poor_multi                        │
    │ $M_0$ (el IPM)    │ c_censored      │ toda la población │ svy: mean c_censored                        │
    │ $A$  (intensidad) │ c_equal         │ solo los pobres   │ svy, subpop(if poor_multi==1): mean c_equal │
    └───────────────────┴─────────────────┴───────────────────┴─────────────────────────────────────────────┘

    De ahí sale sola la identidad  $M_0 = H * A$.

    La clave: $M_0$ y $A$ se calculan con la MISMA suma arriba y distinto divisor abajo.
    Llamemos:

        S = Σ c_censored   suma del puntaje censurado sobre TODOS los hogares.
                           Los no pobres aportan 0 (su puntaje ya fue censurado),
                           así que S es, en realidad, la privación de los pobres.
        n = población total
        q = número de pobres          →   H = q / n

    Entonces:

        M_0 = S / n     ← la privación de los pobres repartida entre TODA la población
        A   = S / q     ← la misma privación repartida solo entre LOS POBRES

    Y al dividir una por otra, el total poblacional se cancela:

        M_0 / H  =  (S / n) / (q / n)  =  S / q  =  A     →   $M_0 = H * A$

    En palabras: $H$ dice a cuánta gente le pasa, $A$ dice qué tan grave lo tienen, y
    $M_0$ combina ambas cosas. Pasar de $A$ a $M_0$ es diluir la privación media de los
    pobres en el total de la población, y el factor de dilución es justamente $H$.

    (Todas las sumas y conteos van ponderados por hhweight; de eso se encarga svy.)

    Nota sobre $A$: entre los pobres, c_equal y c_censored valen lo mismo, así que
    promediar cualquiera de las dos da idéntico resultado. Lo que NO da igual es usar
    `if` en vez de subpop(): el `if` recorta la muestra y estropea el cálculo de la
    varianza bajo diseño complejo, mientras que subpop() mantiene la muestra completa
    y restringe solo el promedio.
*/

*------------------------------------------------------------------
* 3. ESTIMACIÓN DE H, A y M0 CON DISEÑO MUESTRAL COMPLEJO
*    Se usa svy: mean (comando base de Stata, sin ado externos).
*    Para desagregaciones, se usa subpop() —no if— para preservar
*    la estimación correcta de la varianza con el diseño complejo.
*    En cada nivel de agregación hacen falta DOS llamadas a svy: mean:
*      1a) svy: mean poor_multi c_censored               -> H y M0
*      1b) svy, subpop(if poor_multi==1): mean c_equal   -> A
*    Ojo: subpop() es opción de svy, no de mean; por eso va antes
*    de los dos puntos.
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
