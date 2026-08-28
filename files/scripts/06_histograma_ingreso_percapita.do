/*==================================================================
 PROYECTO:      Medida de Pobreza Multidimensional (IPM / MPM)
                Guinea Ecuatorial (ENH2-2023)
 SCRIPT:        06_histograma_ingreso_percapita.do
 --------------------------------------------------------------------
 PROPÓSITO:
   Dos figuras de la distribución del gasto per cápita diario (USD PPA
   2021, variable pcexp_ppp), ambas con la línea de pobreza de 3.00
   USD PPA 2021 (mismo umbral que dep_poor1 en 01_privaciones_MPM.do):

     FIGURA 1 (histograma): bins de 1 USD (0-1, >1-2, ..., >9-10, >10).
     FIGURA 2 (joyplot / ridgeline): distribución NACIONAL completa en
       escala log, adaptada del código de referencia del capítulo de
       Pobreza Monetaria (joyplot por área/provincia) pero con una
       sola curva (Guinea Ecuatorial, nacional), sin desagregar.

   Ambas usan la MISMA base individual que 01_privaciones_MPM.do
   ("$gdData/${database}" = CleanDB_Individual_POV.dta) y la misma
   variable de bienestar (pcexp_ppp) que ese script usa para construir
   dep_poor1.

 VARIABLES CLAVE:
   pcexp_ppp  -> gasto per cápita diario, USD PPA 2021 (misma variable
                 que welfare_ppp en 01_privaciones_MPM.do).
   weight_hh  -> peso del hogar. Como la base está a nivel individual
                 (cada fila = una persona, con el peso de su hogar ya
                 asignado), usarlo como [iw=] al colapsar por persona
                 produce directamente una distribución poblacional
                 (equivalente al "pesos_personas" de la versión
                 original de este script).

 INPUTS ESPERADOS:
   "$gdData/${database}" (globals definidos en 00_maestro.do). Si el
   script se corre de forma independiente -sin pasar por
   00_maestro.do-, más abajo se definen los mismos globals con sus
   valores por defecto.

 OUTPUT:
   "${gdFig}/histograma_ingreso_percapita.png"
==================================================================*/

*-------------------------------------------------------------------
* Globals de respaldo: solo se definen si el script corre solo (fuera
* de 00_maestro.do). Si ya vienen definidos por el maestro, no se
* tocan.
*-------------------------------------------------------------------
if ("$gdRaiz" == "") {
    global gdRaiz   "/Users/estefania/Library/CloudStorage/OneDrive-Personal/Estefania/04-Other/Curso_MPM"
    global gdDo     "$gdRaiz/Web_site/`c(username)'/files/scripts"
    global gdData   "$gdRaiz/1-Data"
    global gdOutput "$gdRaiz/2-Resultados"
    global gdFig    "${gdOutput}/Figures"
    global database "CleanDB_Individual_POV.dta"
}
capture mkdir "${gdFig}"

*-------------------------------------------------------------------
* Base individual de la encuesta (misma que 01_privaciones_MPM.do)
*-------------------------------------------------------------------
use "$gdData/${database}", clear

* Keep the original individual-level dataset unchanged
preserve

* Retain valid observations
keep if !missing(pcexp_ppp, weight_hh)
keep if inrange(pcexp_ppp, 0, 100)
keep if weight_hh > 0

*-------------------------------------------------------------------
* Línea de pobreza monetaria: MISMO umbral que dep_poor1 en
* 01_privaciones_MPM.do (3.00 USD PPA 2021). Se define UNA sola vez
* aquí y se reutiliza tanto para construir los bins como para dibujar
* la línea vertical en el gráfico, así el bin que la contiene queda
* partido EXACTAMENTE en `povline' en vez de depender de que coincida
* "por casualidad" con un borde entero.
*-------------------------------------------------------------------
local povline = 3

* Bordes de los bins: 0,1,2,...,10, insertando `povline' como borde
* adicional si todavía no coincide con uno de ellos (por si algún día
* se usa un umbral no entero, p.ej. 8.30 de la variante MPMplus).
local edges "0"
forvalues e = 1/10 {
    if (`povline' > `e' - 1 & `povline' < `e') local edges "`edges' `povline'"
    local edges "`edges' `e'"
}
local nedges  : word count `edges'
local nbins   = `nedges' - 1
local top     : word `nedges' of `edges'
local lastbin = `nbins' + 1

* Create income bins: 0-`povline', ..., >`top' (`povline' queda como
* borde exacto entre dos bins, no en medio de uno)
gen byte bin_income = .
forvalues i = 1/`nbins' {
    local lo : word `i' of `edges'
    local j  = `i' + 1
    local hi : word `j' of `edges'
    if (`i' == 1) {
        replace bin_income = `i' if inrange(pcexp_ppp, `lo', `hi')
    }
    else {
        replace bin_income = `i' if pcexp_ppp > `lo' & pcexp_ppp <= `hi'
    }
}
replace bin_income = `lastbin' if pcexp_ppp > `top'

* Apply population weights and calculate shares
gen double weighted_population = 1

collapse (sum) weighted_population [iw=weight_hh], ///
    by(bin_income)

egen double total_population = total(weighted_population)
gen double share = 100 * weighted_population / total_population

* Label the bins (generadas de los mismos bordes `edges', así el
* corte de `povline' aparece con su propia etiqueta, p.ej. "2-3" y
* "3-4" en vez de perderse dentro de un bin más ancho)
label define income_bins `lastbin' "Más de `top'", replace
forvalues i = 1/`nbins' {
    local lo : word `i' of `edges'
    local j  = `i' + 1
    local hi : word `j' of `edges'
    local lo_s = strtrim(cond(`lo' == int(`lo'), string(`lo', "%2.0f"), string(`lo', "%4.2f")))
    local hi_s = strtrim(cond(`hi' == int(`hi'), string(`hi', "%2.0f"), string(`hi', "%4.2f")))
    label define income_bins `i' "`lo_s'-`hi_s'", modify
}

label values bin_income income_bins

* Posición de la línea de pobreza en el eje de bins (categórico, 1 a
* `lastbin'): `povline' es el borde que cierra el bin `below_bin' y
* abre el siguiente, así que la línea se dibuja a la mitad, entre
* ambos.
local povline_pos : list posof "`povline'" in edges
local below_bin    = `povline_pos' - 1
local povline_bin  = `povline_pos' - 0.5

* Colores (mismos que en la presentación IPM): RGB equivalentes a los
* hex del proyecto, para no depender de que Stata reconozca hex crudo.
*   9CC13B (verde,  no privado / > línea de pobreza) -> "156 193 59"
*   B35751 (naranja,   privado / <= línea de pobreza) -> "179 87 81"
*   E8603C (rojo,   línea de pobreza)                 -> "232 96 60"
local col_above "156 193 59"
local col_below "179 87 81"
local col_line  "232 96 60"

* Un valor de `share' por bin, partido en dos variables (una por
* debajo y otra por encima de la línea de pobreza) para poder pintar
* cada barra de un color distinto.
gen double share_below = share if bin_income <= `below_bin'
gen double share_above = share if bin_income >  `below_bin'

* Plot population share in each income bin
twoway (bar share_below bin_income, barwidth(0.95) color("`col_below'")) ///
       (bar share_above bin_income, barwidth(0.95) color("`col_above'")) ///
    , ///
    xline(`povline_bin', lcolor("`col_line'") lpattern(dash) lwidth(medthick)) ///
    text(38 `=`povline_bin'+0.15' "Línea de pobreza" "US{c $|}`povline' PPA 2021", ///
        place(e) color("`col_line'") size(small) justification(left)) ///
    xlabel(1(1)`lastbin', valuelabel angle(45) grid glp(dot) glc(black*0.2)) ///
    ylabel(0(10)40, angle(horizontal) grid glp(dot) glc(black*0.2)) ///
    xtitle("Consumo per cápita diario (USD en PPA 2021)") ///
    ytitle("Porcentaje de la población (%)") ///
    title("") ///
    legend(off) ///
    graphregion(color(white))

graph export "${gdFig}/histograma_ingreso_percapita.png", replace width(2000)

restore


/*==================================================================
 FIGURA 2: Joyplot (ridgeline) — distribución nacional del gasto per
 cápita, en escala log, con la línea de pobreza de US$3 PPA 2021.

 Adaptado del código de referencia "Figure: Joyplot" del capítulo de
 Pobreza Monetaria, que dibuja un ridgeline por área (Malabo/Resto
 urbano/Rural) o por provincia, con `GTpc_dr` (XAF mensuales) y peso
 `weight_hh*hhsize` (porque esa base es a nivel de HOGAR). Aquí:
   - Se usa una única curva: la distribución NACIONAL completa de
     Guinea Ecuatorial (sin separar por área ni provincia).
   - La variable es `pcexp_ppp` (USD PPA 2021 diarios), no GTpc_dr.
   - El peso es `weight_hh` solo (sin *hhsize): la base
     CleanDB_Individual_POV.dta ya está a nivel de PERSONA, con el
     peso del hogar asignado a cada una, así que `weight_hh' ya
     representa el peso poblacional (igual que en la Figura 1).
   - Se agrega la línea de pobreza de US$3 PPA 2021 (dep_poor1 en
     01_privaciones_MPM.do), ausente en el código de referencia.
==================================================================*/

*-------------------------------------------------------------------
* `joyplot` (ridgeline plots): el paquete público de SSC NO acepta
* weights ("weights not allowed", r(101)). El código de referencia
* usa una versión propia que sí los soporta (`syntax varname [if]
* [in] [aw/], ...`), cargada con `run` en vez de por el ado-path
* -exactamente como en el capítulo de Pobreza Monetaria-, así que
* hacemos lo mismo aquí con la copia guardada en "$gdDo/_adofiles/".
*-------------------------------------------------------------------
capture program drop joyplot
capture program drop _rangevar
// run "$gdDo/_adofiles/joyplot.ado"
run "/Users/estefania/Library/CloudStorage/OneDrive-Personal/Estefania/04-Other/Curso_MPM/Web_site/Estefania/files/scripts/_adofiles/joyplot.ado"
* `colorpalette` (usado adentro de joyplot.ado) sí depende de paquetes
* públicos de SSC; esos se instalan solo si todavía no están.
// foreach pkg in palettes colrspace {
//     capture which `pkg'
//     if _rc != 0 {
//         di as text "El paquete '`pkg'' no está instalado. Se instalará ahora."
//         ssc install `pkg', replace
//     }
// }

preserve

use "$gdData/${database}", clear

keep if !missing(pcexp_ppp, weight_hh)
keep if inrange(pcexp_ppp, 0, 100)
keep if weight_hh > 0

* Escala logarítmica: el gasto per cápita es muy asimétrico a la
* derecha (ver Figura 1); en log, la forma de la distribución (y la
* comparación con la línea de pobreza) se aprecia mucho mejor.
gen double log_pcexp = ln(pcexp_ppp)
label var log_pcexp "Gasto per cápita diario (USD PPA 2021, escala log)"

* Una sola categoría: distribución NACIONAL completa (a diferencia
* del código de referencia, aquí NO se desagrega por área/provincia).
gen byte nacional = 1
label define nacional_lbl 1 " "
label val nacional nacional_lbl

* Línea de pobreza de US$3 en PPA 2021 (mismo umbral que la Figura 1 y
* que dep_poor1 en 01_privaciones_MPM.do), en la misma escala log del
* eje x.
local povline   = 3
local povline_x = ln(`povline')
local col_line  "232 96 60"   // E8603C, mismo rojo que la Figura 1

joyplot log_pcexp [aw = weight_hh], byvar(nacional) bwadj(1) dadj(2) ///
    colorpalette(viridis, opacity(80) intensity(0.9)) ///
    ytitle("Proporción de la población", size(medsmall)) ///
    xtitle("Consumo per cápita diario (USD en PPA 2021)", size(medsmall)) ///
    yscale(lstyle(none)) ///
    xlabel(0 "1" 0.69 "2" 1.61 "5" 2.30 "10" 3.00 "20" 3.91 "50" 4.61 "100", ///
        grid glp(dot) glc(black*0.2)) ///
    ylabel(, grid glp(dot) glc(black*0.2)) ///
  xline(`povline_x', lcolor("`col_line'") lpattern(dash) lwidth(medthick)) ///
    graphregion(color(white))


graph export "${gdFig}/joyplot_consumo_nacional.png", replace width(2000)

restore
