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
 1) ÚNICA RUTA A EDITAR: carpeta de trabajo del proyecto
    Es la carpeta que contiene los do-files del pipeline y la base
    de datos de la encuesta, y donde se guardarán los resultados.
    Ver la sección 2 para el detalle, y el README.md para el
    diagrama completo.

    Si la dejas vacía (""), se usará la carpeta de trabajo actual de
    Stata: para eso, abre este do-file haciendo doble clic sobre él
    (o usa File > Change working directory... y selecciónala).
------------------------------------------------------------------*/
* -- EDITA AQUÍ (y solo aquí): ruta de la carpeta de tu proyecto --

     global gdRaiz "EDITA AQUÍ"

if ("$gdRaiz" == "") {
    global gdRaiz "`c(pwd)'"
    di as txt "Se usará la carpeta de trabajo actual: $gdRaiz"
    di as txt "Si no es la carpeta correcta, configura el global gdRaiz arriba."
}

capture cd "$gdRaiz"
if _rc!=0 {
    di as error "La ruta del global gdRaiz no existe: $gdRaiz"
    di as error "Corrígela en 00_maestro.do (línea con -- EDITA AQUÍ --) antes de correr este script."
    error 601
}

/*------------------------------------------------------------------
 2) RUTAS DERIVADAS DE $gdRaiz (no deberías necesitar tocar esto)
    Todo el proyecto vive en una sola carpeta: los do-files del
    pipeline, los microdatos de la encuesta y los productos que se
    generan (.dta, Excel, figuras) están y se escriben en $gdRaiz.
    Por eso las rutas de trabajo apuntan todas al mismo directorio:

        $gdDo      -> do-files del pipeline
        $gdData    -> microdatos de la encuesta
        $gdOutput  -> todo lo que el pipeline genera
        $gdExcel / $gdFig / $gdStata -> Excel, figuras y .dta

    Si tu proyecto separa estos productos en subcarpetas, ajusta las
    líneas de abajo (y solo estas).
------------------------------------------------------------------*/
global gdDo        "$gdRaiz"
global gdData      "$gdRaiz"
global gdOutput    "$gdRaiz"
    global gdExcel    "$gdOutput"
    global gdFig      "$gdOutput"
    global gdStata    "$gdOutput"

/*------------------------------------------------------------------
 3) Parametros para la ejecucion 
------------------------------------------------------------------*/
global language "SPA"                           // Idioma de las etiquetas/salidas: "SPA" o "ENG"
global database "Individuals_data.dta"          //  Base training: Individuals_data.dta 
global MPM "MPM"                                // MPM o MPMplus
global methodology "mpitb"                      // "mpitb" o "manual".
                                                //   "mpitb"  -> pipeline completo: calcula, guarda
                                                //               los .dta Y exporta el Excel.
                                                //   "manual" -> versión didáctica (solo H, A y M0).
                                                //               NO exporta a Excel: ver Paso 3.

* Fuente de las figuras (consistencia visual entre gráficos)
graph set window fontface "Arial Narrow"

/*------------------------------------------------------------------
 4) Crear carpetas de salida si no existen
    (las que el pipeline usa por variante de MPM e idioma)
------------------------------------------------------------------*/
*If needed, create directories, and sub-directories used in the process 
foreach d in "${gdStata}/Data Clean $MPM" "${gdExcel}/$MPM" ///
             "${gdExcel}/$MPM/$language"   {
	capture mkdir "`d'"
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
* POR QUÉ ESTE PASO ESTÁ CONDICIONADO
*   04_exportar_figuras.do lee "${MPM}_results.dta" y espera la
*   estructura que produce `mpitb`: subgrupo (subg) NUMÉRICO, columna
*   subg_name, nivel de análisis "cities" y las medidas por indicador
*   "hd"/"hdk". El camino manual (03_calculo_mpm.do) guarda un archivo
*   más chico: solo H, A y M0, con subg como TEXTO. Si se le pasa ese
*   archivo, 04 se detiene con "type mismatch" (r(109)) en la hoja
*   "Headcount". Por eso solo se ejecuta en el camino "mpitb".
if ("$methodology" == "mpitb") {
  include "$gdDo/04_exportar_figuras.do"
}
else {
  di as error "AVISO: no se exportó nada a Excel."
  di as error "       Con \$methodology = $methodology el archivo de resultados es"
  di as error "       reducido (solo H, A y M0) e incompatible con 04_exportar_figuras.do."
  di as error "       Para generar ${MPM}_QNG.xlsx, ponga \$methodology = mpitb arriba."
}

/*------------------------------------------------------------------
 4) Mensaje final con las rutas de salida (útil para ubicar productos)
------------------------------------------------------------------*/
display "Datos (.dta) exportados en: ${gdStata}/Data Clean ${MPM}"
if ("$methodology" == "mpitb") {
    display "Excel exportado en:         ${gdExcel}/${MPM}/${language}/${MPM}_QNG.xlsx"
}
* Nota: la Parte 2 (figuras nativas de Stata) ya no forma parte de
* 04_exportar_figuras.do, así que este pipeline no escribe figuras.
include "$gdDo/05_tabla_PEA_curso.do"
