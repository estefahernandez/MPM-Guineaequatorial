/*==================================================================
 PROYECTO:      Medida de Pobreza Multidimensional (IPM / MPM)
                Guinea Ecuatorial (ENH2-2023)
 SCRIPT:        00_maestro.do
 AUTOR ORIGINAL: Banco Mundial, proyecto GNQ-PA
 --------------------------------------------------------------------
 PROPÓSITO
   Este .do es el "orquestador" del pipeline: no calcula nada por sí
   mismo, solo define las rutas de trabajo (globals) y llama, en
   orden, a cada uno de los 4 módulos de este proyecto mediante
   `include`. `include` (a diferencia de `do`) comparte el mismo
   espacio de macros/globals con el script que lo llama, por lo que
   todos los módulos pueden usar los globals definidos aquí.

 ORDEN DE EJECUCIÓN (ver README.md para detalle de cada paso)
   01_limpieza.do            -> construye indicadores base
   02_privaciones.do         -> construye variables binarias 0/1
                                 de privación por indicador
   03_mpitb.do                -> calcula el MPM con `mpitb`
   04_exportar_figuras.do    -> TODAS las figuras/cuadros: Parte 1
                                 (Excel) y Parte 2 (gráficos Stata)
==================================================================*/

version 18
clear all
set more off

*Install packages used in the process
local commands = "ineqdeco grstyle mpitb apoverty vselect missings" 
local commands_added = "elasticregress"
local commands_edited = "`commands' `commands_added'"
foreach c of local commands_edited {
	qui capture which `c' 
	qui if _rc!=0 {
		noisily di "This command requires '`c''. The package will now be downloaded and installed."
		ssc install `c'
	}
	di "Command '`c'' is already installed."
}

/*------------------------------------------------------------------
 1) ÚNICA RUTA A EDITAR: carpeta raíz del proyecto
    Debe ser la carpeta que contiene (o va a contener) las subcarpetas
    de datos, resultados y, opcionalmente, la carpeta de productos
    editoriales. Ver la sección 2 para el detalle de la estructura
    esperada, y el README.md para el diagrama completo.
------------------------------------------------------------------*/
* -- EDITA AQUÍ (y solo aquí): ruta raíz de tu proyecto --

     global gdRaiz "EDITA AQUÍ"

if ("$gdRaiz" == "") {
    di as error "Configura el global gdRaiz en 00_maestro.do (línea con -- EDITA AQUÍ --) antes de correr este script."
    error 1
}

/*------------------------------------------------------------------
 2) RUTAS DERIVADAS DE $gdRaiz (no deberías necesitar tocar esto)
    Estructura de subcarpetas esperada debajo de $gdRaiz:
        
        Do-files/                         -> $gdDo   (esta misma carpeta,
                                              los 5 do-files del pipeline)
        1-Data/                           -> $gdData (microdatos de la
                                              encuesta y bases de
                                              comparación internacional)
        2-Resultados/                     -> $gdOutput (todo lo que el
                                              pipeline genera: .dta,
                                              Excel, figuras)

    Si tu proyecto ya usa otros nombres de subcarpeta, ajusta las 3
    líneas de abajo (y solo estas 3).
------------------------------------------------------------------*/
global gdDo        "$gdRaiz/Web_site/`c(username)'/files/scripts" //  ("$gdRaiz/Do-files")
global gdData      "$gdRaiz/1-Data"
global gdOutput    "$gdRaiz/2-Resultados"
    global gdExcel    "${gdOutput}/Excel"
    global gdFig      "${gdOutput}/Figures"
    global gdStata    "${gdOutput}/Stata"

/*------------------------------------------------------------------
 3) Parametros para la ejecucion 
------------------------------------------------------------------*/
global language "SPA"                           // Idioma de las etiquetas/salidas: "SPA" o "ENG"
global database "CleanDB_Individual_POV.dta"    //  Base training: Individuals_data.dta - Base PEA completa: CleanDB_Individual_POV.dta
global MPM "MPM"                                // MPM o MPMplus
global methodology "manual"                     // mpitb syntax vs manual

* Fuente de las figuras (consistencia visual entre gráficos)
graph set window fontface "Arial Narrow"

/*------------------------------------------------------------------
 4) Crear carpetas de salida si no existen
    (Data, Data/temp, Excel, Figures, y sus subcarpetas por variante
    de MPM e idioma)
------------------------------------------------------------------*/
*If needed, create directories, and sub-directories used in the process 
foreach d in "${gdExcel}" "${gdFig}" ///
             "${gdStata}/Data Clean $MPM" "${gdExcel}/$MPM" ///
             "${gdExcel}/$MPM/$language"   {
	confirmdir "`d'" 
	if _rc!=0 mkdir "`d'" 
}

/*==================================================================
 5) EJECUCIÓN DEL PIPELINE
  Cada paso del pipeline es un módulo independiente, que se llama con `include`. Ver README.md para el detalle de cada paso.
==================================================================*/

*---------------------------------------------------------
* Paso 1 | Construcción de variables binarias de privación
*---------------------------------------------------------
if ("$MPM" == "MPM") {
    include "$gdDo/01_privaciones_MPM.do"
}
else if ("$MPM" == "MPMplus") {
    include "$gdDo/01_privaciones_MPMplus.do"
}

*---------------------------------------------------------
* Paso 2 | Cálculo del IPM con el comando oficial `mpitb`
*---------------------------------------------------------
// ssc install mpitb
if ("$methodology" == "mpitb") {
    include "$gdDo/03_calculo_mpm_mpitb.do"
}
else if ("$methodology" == "manual") {
    include "$gdDo/03_calculo_mpm.do"
}

*---------------------------------------------------------
* Paso 3 | Todas las figuras y cuadros: Parte 1 (Excel) y
* Parte 2 (gráficos nativos de Stata). Ver comentarios dentro
* de 04_exportar_figuras.do para el detalle de cada sub-bloque
* y de los 2 bloques opcionales (Venn, mapas) que quedan
* deshabilitados por defecto.
*---------------------------------------------------------
if ("$methodology" == "mpitb") { // Construido para el conjunto amplio de indicadores 
  include "$gdDo/04_exportar_figuras.do"
}

/*------------------------------------------------------------------
 4) Mensaje final con las rutas de salida (útil para ubicar productos)
------------------------------------------------------------------*/
display "Datos (.dta) exportados en: ${gdStata}/Data Clean ${MPM}"
display "Excel exportado en:         ${gdExcel}/${MPM}/${language}"
display "Figuras exportadas en:       ${gdFig}/${MPM}/${language}"
include "$gdDo/05_tabla_PEA_curso.do"

