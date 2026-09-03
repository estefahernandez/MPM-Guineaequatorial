/*==================================================================
 PROYECTO : Curso de Medición de Pobreza Multidimensional (MPM / IPM)
            Guinea Ecuatorial - ENH2 2023
 SCRIPT   : 03_calculo_mpm_mpitb.do
 SESIÓN   : 2 - Cálculo del IPM y sus descomposiciones con `mpitb`
 --------------------------------------------------------------------
 QUÉ HACE ESTE ARCHIVO, EN UNA FRASE
   Toma la base donde ya sabemos, hogar por hogar, en qué cosas está
   privado (un 1) y en cuáles no (un 0), y calcula el Índice de
   Pobreza Multidimensional (IPM/MPM): cuánta gente es pobre (H), qué
   tan pobre es esa gente (A) y el índice que resume las dos cosas
   (M0 = H x A), con sus errores estándar y sus desagregaciones.

 NUESTRA GUÍA TEÓRICA
   Suppa, N. (2023). "mpitb: A toolbox for multidimensional poverty
   indices". The Stata Journal 23(3), 625-657.
   Ese artículo es el manual oficial del paquete `mpitb` y la base
   teórica de todo lo que hacemos aquí. En cada paso citamos la
   sección exacta del artículo (por ejemplo: Suppa 2023, sección 3.2)
   para que puedas ir a leerla.
   El método que implementa `mpitb` es el de Alkire y Foster (2011),
   resumido en Suppa (2023, sección 2, pp. 627-628).

 CÓMO SE LEE ESTE ARCHIVO
   Está escrito en PASOS numerados. Cada paso tiene siempre:
       IDEA SIMPLE  -> la explicación en palabras de todos los días
       POR QUÉ      -> de dónde sale (el artículo / el método)
       EL CÓDIGO    -> la línea de Stata, comentada
   Preferimos el código más sencillo y explícito, aunque sea más
   largo, antes que el código corto y elegante que nadie entiende.

 INSUMO (lo que este archivo necesita que ya exista)
   "${gdStata}/Data Clean $MPM/DataDeprivations${MPM}.dta"
   <- lo produce 01_privaciones_MPM.do

 PRODUCTOS (lo que este archivo deja guardado)
   1) "${gdStata}/${MPM}_results.dta"
      Tabla larga de resultados: una fila por cada número estimado.
   2) "${gdStata}/${MPM}_results_microdata.dta"
      Microdato de hogares con el puntaje de privación (c_equal) y la
      marca de pobre multidimensional (poor_multi).
   3) El frame "myresults" en memoria (para mirar los resultados sin
      abrir ningún archivo).
   Estos tres productos son los que después usan 04_exportar_figuras.do
   y 05_tabla_PEA_curso.do, así que NO hay que cambiarles el nombre.

 CÓMO CORRERLO
   Normalmente no se corre solo: lo llama 00_maestro.do cuando el
   global $methodology vale "mpitb". Si quieres correrlo por separado,
   corre antes 00_maestro.do (rutas) y 01_privaciones_MPM.do.

 REQUISITO
   El paquete `mpitb` debe estar instalado (Suppa 2023, sección 7):
       ssc install moremata, replace
       ssc install mpitb, replace
==================================================================*/


/*==================================================================
 EL MÉTODO EN 5 PASOS (Suppa 2023, sección 2, pp. 627-628)

 Imagina que a cada hogar le hacemos una lista de chequeo.

 PASO A. La lista de carencias.
         Miramos cada indicador d y anotamos:
             1 = "a este hogar le falta esto"  (y_id < z_d)
             0 = "a este hogar no le falta"
         z_d es el umbral: la raya que separa "le falta" de "no le
         falta" (por ejemplo: no tener electricidad).
         Esa lista de unos y ceros ya la construyó 01_privaciones.

 PASO B. No todas las carencias pesan lo mismo.
         A cada indicador d le damos un peso w_d. Es como repartir
         una pizza: todos los pedazos juntos tienen que dar la pizza
         completa, es decir, la suma de todos los pesos es 1.

 PASO C. El puntaje de privación de cada hogar.
             c_i = suma de los pesos de las carencias que SÍ tiene
         Va de 0 (no le falta nada) a 1 (le falta todo).

 PASO D. Decidir cuánto es "demasiado": el corte k.
         Aquí usamos k = 33% (un tercio). Entonces:
             si c_i >= 1/3  ->  el hogar es POBRE MULTIDIMENSIONAL
             si c_i <  1/3  ->  no lo es (y su puntaje se pone en 0;
                                a eso se le llama "censurar")

 PASO E. Contar. Salen las tres medidas del método:
             H  = de cada 100 personas, cuántas son pobres
                  (incidencia)
             A  = entre las personas pobres, qué porcentaje de las
                  privaciones posibles sufren en promedio
                  (intensidad)
             M0 = H x A  -> el IPM (adjusted headcount ratio)

         Y además, por cada indicador (Suppa 2023, pp. 627-628):
             hd   = % de gente privada en ese indicador (sin importar
                    si es pobre o no)               -> "no censurado"
             hdk  = % de gente privada en ese indicador Y además
                    pobre multidimensional          -> "censurado"
             actb = cuánto aporta ese indicador al M0 (w_d * hdk)
             pctb = ese aporte en porcentaje del M0
==================================================================*/


/*==================================================================
                    PARTE 1: PREPARAR LA COMIDA
        (dejar la base exactamente como `mpitb` la necesita)
==================================================================*/

*-------------------------------------------------------------------
* PASO 1 | Abrir la base de privaciones
*-------------------------------------------------------------------
* IDEA SIMPLE
*   Sacamos de la nevera la base que dejó lista el archivo anterior
*   (01_privaciones_MPM.do). En esa base ya están los unos y ceros:
*   "a este hogar le falta electricidad", "a este no", etc.
*
* POR QUÉ
*   `mpitb` no construye privaciones: las recibe ya construidas. El
*   artículo lo dice al presentar su base de ejemplo syn_cdta.dta:
*   son "cleaned synthetic data providing already binary deprivation
*   indicators" (Suppa 2023, p. 642).
*
* EL CÓDIGO
*   `use ... , clear` = abre este archivo y bota lo que hubiera antes.
*-------------------------------------------------------------------
use "${gdStata}/Data Clean $MPM/DataDeprivations${MPM}.dta", clear


*-------------------------------------------------------------------
* PASO 2 | Quedarnos solo con las variables que vamos a usar
*-------------------------------------------------------------------
* IDEA SIMPLE
*   Antes de salir de viaje sacamos de la maleta lo que no vamos a
*   usar. Así pesa menos y encontramos rápido lo que sí necesitamos.
*
* POR QUÉ
*   Nos quedamos con cuatro tipos de variables:
*     (a) el identificador del hogar (hhid);
*     (b) las 6 privaciones (las que empiezan con dep_);
*     (c) lo que necesita el diseño muestral (weight_hh, hhsize,
*         cod_provincia, cod_CV_CP);
*     (d) las variables por las que queremos desagregar y las que
*         usan los archivos 04 y 05 más adelante.
*
* EL CÓDIGO
*   `keep` = "quédate solo con estas variables y borra el resto".
*   Las tres barras /// significan "esta línea sigue en la de abajo".
*-------------------------------------------------------------------
keep hhid provincia cod_provincia cod_CV_CP q1_03_edad hhsize weight_hh ///
     pcexp_ppp educat7 asistencia_escolar electricity imp_san_rec imp_wat_rec ///
     dep_educ_com dep_educ_enr dep_infra_elec dep_infra_imps ///
     dep_infra_impw dep_poor1 quintile cities //welfare_ppp


*-------------------------------------------------------------------
* PASO 3 | Ponerle a cada indicador un apodo corto
*-------------------------------------------------------------------
* IDEA SIMPLE
*   Cada indicador tiene un nombre larguísimo. Le ponemos un apodo
*   corto, como cuando a "Guillermo" le decimos "Memo".
*
* POR QUÉ
*   El apodo que pongamos aquí es EXACTAMENTE el nombre que va a
*   aparecer después en todas las tablas de resultados. Además el
*   artículo pide nombres cortos: "Short variable names are
*   recommended (at most 10 characters are permitted)"
*   (Suppa 2023, sección 3.1.2, p. 629).
*
* LA REGLA DE LOS APODOS
*   e_ = dimensión educación     i_ = dimensión infraestructura
*   (y la dimensión monetaria tiene un solo indicador: poor1)
*
*   Nombre largo       ->  Apodo    Qué significa
*   ------------------     ------   -------------------------------
*   dep_educ_com       ->  e_com    ningún adulto terminó primaria
*   dep_educ_enr       ->  e_enr    hay un niño sin matricular
*   dep_infra_elec     ->  i_elec   sin electricidad
*   dep_infra_imps     ->  i_imps   sin saneamiento mejorado
*   dep_infra_impw     ->  i_impw   sin agua mejorada
*   dep_poor1          ->  poor1    pobre monetario
*
* EL CÓDIGO
*   `rename viejo nuevo` = cámbiale el nombre a una variable.
*   Lo hacemos de a uno, uno por línea. Se podría hacer en 3 líneas
*   con comodines (rename dep_* *), pero así de a uno se ve clarito
*   qué apodo le tocó a cada quien.
*-------------------------------------------------------------------
rename dep_educ_com    e_com
rename dep_educ_enr    e_enr
rename dep_infra_elec  i_elec
rename dep_infra_imps  i_imps
rename dep_infra_impw  i_impw
rename dep_poor1       poor1


*-------------------------------------------------------------------
* PASO 4 | Dejar una sola fila por hogar
*-------------------------------------------------------------------
* IDEA SIMPLE
*   La base viene con una fila por PERSONA. Como el IPM se decide a
*   nivel de HOGAR (si el hogar es pobre, lo son todos sus miembros),
*   nos quedamos con una sola fila por hogar: como si de cada familia
*   entrara una sola persona a la foto, en representación de todos.
*
* POR QUÉ
*   "data constraints often lead to an identification at the
*   household level" (Suppa 2023, p. 627). La privación se observa
*   para el hogar completo: si en la casa no hay agua, no la hay para
*   nadie de la casa.
*
* OJO
*   Esto NO significa que los resultados sean "por hogar". En el
*   PASO 5 le devolvemos a cada hogar el peso de todas las personas
*   que viven en él, y así los resultados vuelven a hablar de gente.
*
* EL CÓDIGO
*   `duplicates drop hhid, force` = "si hay varias filas con el mismo
*   hhid, déjame solo la primera".
*-------------------------------------------------------------------
duplicates drop hhid, force


*-------------------------------------------------------------------
* PASO 5 | El ponderador: que cada hogar valga por su gente
*-------------------------------------------------------------------
* IDEA SIMPLE
*   Una encuesta no entrevista al país entero: entrevista a una
*   muestra. El ponderador dice "este hogar representa a X hogares
*   parecidos del país". Como en el paso anterior nos quedamos con
*   una fila por hogar, multiplicamos ese peso por el número de
*   personas del hogar: así una familia de 6 pesa el triple que una
*   de 2, que es lo justo si queremos hablar de PERSONAS pobres.
*
* POR QUÉ
*   El IPM se reporta como porcentaje de la POBLACIÓN, no de los
*   hogares (Suppa 2023, sección 2: H = q/N, donde N son personas).
*
* EL CÓDIGO
*   `gen nueva = fórmula` = crea una variable nueva.
*-------------------------------------------------------------------
gen hhweight = weight_hh * hhsize


*-------------------------------------------------------------------
* PASO 6 | El estrato: en qué "cajita" del muestreo cayó cada hogar
*-------------------------------------------------------------------
* IDEA SIMPLE
*   La encuesta no se sorteó entre todos los hogares del país de una
*   sola bolsa. Se hicieron varias bolsas (estratos) -por ejemplo,
*   "Litoral urbano", "Litoral rural", "Kie Ntem urbano"...- y se
*   sorteó dentro de cada bolsa. Aquí reconstruimos esa cajita
*   combinando provincia con área (urbano/rural).
*
* POR QUÉ
*   Si no le contamos a Stata cómo se hizo el sorteo, los errores
*   estándar salen mal. `mpitb` calcula errores estándar que "may
*   account for complex survey design" (Suppa 2023, p. 626), pero
*   solo si nosotros se lo declaramos (PASO 7).
*
* EL CÓDIGO
*   `egen nueva = group(a b)` = ponle un número distinto a cada
*   combinación distinta de a y b (1, 2, 3, ...).
*-------------------------------------------------------------------
egen strata = group(cod_provincia cod_CV_CP)


*-------------------------------------------------------------------
* PASO 7 | Declararle a Stata el diseño de la encuesta (svyset)
*-------------------------------------------------------------------
* IDEA SIMPLE
*   Aquí le decimos a Stata, de una vez y para siempre: "estos datos
*   vienen de una encuesta que se hizo así: este es el peso de cada
*   hogar y estas son las cajitas del sorteo". De aquí en adelante
*   Stata lo tiene en cuenta solo.
*
* POR QUÉ
*   El artículo lo hace exactamente igual antes de estimar:
*   "first use svyset to specify the primary sampling unit, the
*   strata, and the sampling weight for each observation"
*   (Suppa 2023, ejemplo 1, p. 642). Y advierte que, si no se hace,
*   "the data are assumed to be obtained through simple random
*   sampling, which is rarely used in practice" (p. 632).
*
* EL CÓDIGO, pedazo por pedazo
*   svyset hhid            -> la unidad que se sorteó (aquí, el hogar)
*   [iw = hhweight]        -> el peso de cada observación (PASO 5)
*   , clear                -> borra cualquier diseño declarado antes
*   strata(strata)         -> las cajitas del sorteo (PASO 6)
*-------------------------------------------------------------------
svyset hhid [iw = hhweight], clear strata(strata)


*-------------------------------------------------------------------
* PASO 8 | Apodos cortos para las variables de desagregación
*-------------------------------------------------------------------
* IDEA SIMPLE
*   Igual que en el PASO 3, pero ahora para las variables con las que
*   vamos a partir el país en pedazos: área y provincia.
*
* POR QUÉ
*   Estos nombres también viajan a la tabla de resultados: aparecerán
*   en la columna `loa` ("level of analysis", nivel de análisis) cada
*   vez que pidamos una desagregación con over() en el PASO 11.
*
* NUESTROS TRES CORTES DEL PAÍS
*   area   = urbano / rural
*   prov   = las 7 provincias
*   cities = Malabo / resto urbano / rural (esta ya se llama así)
*
* EL CÓDIGO
*   Con paréntesis se pueden renombrar dos variables de un tirón: la
*   primera de la izquierda pasa a llamarse la primera de la derecha,
*   y así.
*-------------------------------------------------------------------
rename (cod_CV_CP cod_provincia) (area prov)


/*==================================================================
                 PARTE 2: LA RECETA Y EL CÁLCULO
     (los dos comandos centrales: `mpitb set` y `mpitb est`)
==================================================================*/

*-------------------------------------------------------------------
* PASO 9 | `mpitb set`: escribir la receta del índice
*-------------------------------------------------------------------
* IDEA SIMPLE
*   Todavía no calculamos nada. Solo escribimos la receta y le
*   pegamos una etiqueta con su nombre ("GNQ"), como cuando anotas
*   una receta en una tarjeta y la guardas en el cajón. En la receta
*   decimos qué dimensiones hay y qué indicadores van en cada una.
*
* POR QUÉ
*   "mpitb set specifies the deprivation indicators for an MPI and
*   stores this specification with the currently loaded dataset"
*   (Suppa 2023, sección 3.1, p. 629). Guardar la receta con un
*   nombre permite tener VARIAS recetas sobre la misma base y
*   compararlas (lo usamos en los ejercicios extra del final).
*
* NUESTRA RECETA (la del MPM de Guinea Ecuatorial)
*   Dimensión 1 "educ"  -> e_com, e_enr
*   Dimensión 2 "infra" -> i_elec, i_imps, i_impw
*   Dimensión 3 "mon"   -> poor1
*
* EL CÓDIGO, pedazo por pedazo
*   name(GNQ)                  -> el nombre de la receta (máx. 10 letras)
*   d1(lista, name(educ))      -> los indicadores de la dimensión 1 y
*                                 cómo se llama esa dimensión
*   d2(...), d3(...)           -> lo mismo para las dimensiones 2 y 3
*                                 (se admiten hasta 10: d1 ... d10)
*   description(...)           -> una nota para acordarnos de qué es
*   replace                    -> si ya existía una receta con este
*                                 nombre, la pisa (útil al re-correr)
*
* NOTA: escribimos name() completo; en otros do-files verás la
* abreviatura na(). Son lo mismo.
*-------------------------------------------------------------------
mpitb set, name(GNQ) ///
    d1(e_com e_enr,          name(educ))  ///
    d2(i_elec i_imps i_impw, name(infra)) ///
    d3(poor1,                name(mon))   ///
    description(MPM Guinea Ecuatorial - especificacion del curso) ///
    replace


*-------------------------------------------------------------------
* PASO 10 | Mirar la receta antes de cocinar (`mpitb show`)
*-------------------------------------------------------------------
* IDEA SIMPLE
*   Antes de meter nada al horno, leemos la receta en voz alta para
*   revisar que no se nos haya olvidado un ingrediente.
*
* POR QUÉ
*   "mpitb show displays information about MPIs stored with the
*   current data" (Suppa 2023, sección 3.5, p. 635). Este comando no
*   cambia nada: solo muestra. Es la mejor forma de cachar a tiempo
*   un indicador mal escrito o puesto en la dimensión equivocada.
*-------------------------------------------------------------------
mpitb show, name(GNQ)


*-------------------------------------------------------------------
* PASO 11 | `mpitb est`: aquí SÍ se calcula todo
*-------------------------------------------------------------------
* IDEA SIMPLE
*   Este es el horno. Le entra la receta (GNQ) y le sale TODO:
*   H, A, M0, los números por indicador y los números de cada pedazo
*   del país, cada uno con su margen de error.
*
* POR QUÉ
*   "mpitb est estimates indices and subindices of multidimensional
*   poverty (...) provides standard errors and confidence intervals
*   for most quantities and may take complex survey design into
*   account" (Suppa 2023, sección 3.2, p. 629).
*
* LOS PESOS (lo que hace weights(equal) por dentro)
*   weights(equal) reparte "en partes iguales, dos veces":
*     1) la pizza se parte en 3 pedazos iguales, uno por dimensión
*        -> cada dimensión pesa 1/3
*     2) el pedazo de cada dimensión se reparte en partes iguales
*        entre sus indicadores:
*           educ  tiene 2 indicadores -> 1/3 x 1/2 = 1/6 cada uno
*           infra tiene 3 indicadores -> 1/3 x 1/3 = 1/9 cada uno
*           mon   tiene 1 indicador   -> 1/3 x 1/1 = 1/3
*     Comprobación: 1/6 + 1/6 + 1/9 + 1/9 + 1/9 + 1/3 = 1  (la pizza
*     completa, tal como pide Suppa 2023, p. 627: la suma de w_d = 1)
*
* EL CÓDIGO, OPCIÓN POR OPCIÓN
*   name(GNQ)         Qué receta usar (la del PASO 9).
*   klist(33)         El corte k, en porcentaje: es pobre quien tenga
*                     un puntaje de privación de 33% o más (= 1/3).
*                     Se pueden pedir varios: klist(20 33 50).
*   weights(equal)    Pesos iguales anidados (lo explicado arriba).
*   measures(all)     Calcula las medidas agregadas: M0, H y A.
*   indmeasures(all)  Calcula las medidas por indicador: hdk, actb, pctb.
*   aux(hd)           Agrega el headcount NO censurado (hd): % privado
*                     en cada indicador sin importar si es pobre.
*   svy               Usa el diseño declarado en el PASO 7 para los
*                     errores estándar.
*   over(area prov cities)  Repite todo el cálculo dentro de cada
*                     pedazo del país, además del total nacional.
*   lframe(myresults, replace)  Deja los resultados en un "frame"
*                     (una segunda base abierta en memoria, al lado de
*                     la nuestra, sin pisarla).
*   lsave("...")      Guarda esos mismos resultados en un archivo .dta.
*   dtasave("...")    Guarda el microdato de hogares CON las variables
*                     que fabricó mpitb, entre ellas c_equal (el
*                     puntaje de privación de cada hogar).
*
* CUÁNTO SE DEMORA
*   Es el paso lento del pipeline (son miles de estimaciones, cada una
*   con su error estándar). Stata va imprimiendo el conteo de
*   estimaciones acumuladas mientras trabaja.
*-------------------------------------------------------------------
mpitb est, name(GNQ) ///
    klist(33) ///
    weights(equal) ///
    measures(all) ///
    indmeasures(all) ///
    aux(hd) ///
    svy ///
    over(area prov cities) ///
    lframe(myresults, replace) ///
    lsave("${gdStata}/${MPM}_results.dta", replace) ///
    dtasave("${gdStata}/${MPM}_results_microdata.dta", replace)


/*==================================================================
                  PARTE 3: LEER LOS RESULTADOS
==================================================================*/

*-------------------------------------------------------------------
* PASO 12 | Asomarnos a la tabla de resultados
*-------------------------------------------------------------------
* IDEA SIMPLE
*   `mpitb est` dejó los resultados en una mesa aparte llamada
*   "myresults". Con `cwf` (change working frame) nos paramos en esa
*   mesa para mirarlos. Nuestra base de hogares sigue intacta en la
*   mesa de al lado ("default").
*
* CÓMO ESTÁ ORGANIZADA LA TABLA
*   Cada FILA es UN número estimado. Las columnas dicen qué número es
*   (Suppa 2023, sección 3.8, p. 637, y ejemplo 1, p. 645):
*     b, se        el valor estimado y su error estándar
*     ll, ul       los extremos del intervalo de confianza
*     pval, tval   valor-p y estadístico t
*     measure      qué medida es: M0, H, A, hd, hdk, actb, pctb
*     loa          el nivel: nat, area, prov, cities
*     subg         qué subgrupo dentro de ese nivel (un código)
*     indicator    a qué indicador se refiere (si aplica)
*     k            con qué corte se calculó
*     wgts         con qué esquema de pesos
*-------------------------------------------------------------------
cwf myresults

* Ver la lista completa de columnas de la tabla de resultados.
describe

* Contar cuántas estimaciones hay de cada medida en cada nivel.
* (Es la misma tabla de control que muestra Suppa 2023, p. 645.)
tabulate measure loa

* --- Los tres números principales, a nivel nacional ---
* Se lee: "muéstrame la medida, el valor y el error estándar, solo de
*  las filas donde la medida sea M0, H o A, el nivel sea nacional y el
*  corte sea 33". `noobs` = no muestres el número de fila.
list measure b se if inlist(measure,"M0","H","A") & loa == "nat" & k == 33, noobs

* --- Comparar, indicador por indicador, hd contra hdk ---
*   hd  = % de personas privadas en ese indicador (todas)
*   hdk = % de personas privadas en ese indicador Y además pobres
*   hdk siempre es menor o igual que hd: es la parte "censurada".
* `tabdisp` arma una tablita: filas = indicador, columnas = medida.
* En `k` pedimos 33 y también el missing (.) porque hd no depende de k.
tabdisp indicator measure if inlist(measure,"hd","hdk") & loa == "nat" ///
    & inlist(k,33,.), cellvar(b)

* --- Contribución de cada indicador al M0 ---
*   actb = aporte absoluto (peso x hdk); todos suman M0
*   pctb = ese mismo aporte en % del M0; todos suman 100
* (Suppa 2023, p. 628: M0 = suma de w_d * h_d(k).)
tabdisp indicator measure if inlist(measure,"actb","pctb") & loa == "nat" ///
    & k == 33, cellvar(b)

* Volvemos a pararnos en la mesa principal.
cwf default


/*==================================================================
          PARTE 4: DEJAR LOS PRODUCTOS LISTOS PARA EL PASO 04
==================================================================*/

*-------------------------------------------------------------------
* PASO 13 | Armar el diccionario de nombres de los subgrupos
*-------------------------------------------------------------------
* IDEA SIMPLE
*   En la tabla de resultados los subgrupos salen como números pelados
*   (subg = 1, 2, 3...) y no como nombres. El problema es que el mismo
*   número significa cosas distintas según el nivel: subg==1 es
*   "Urban" si loa=="area", pero es "Malabo" si loa=="cities" y
*   "Annobón" si loa=="prov". Por eso no se puede pegar una sola lista
*   de etiquetas: hay que armar una libretita de traducción con TRES
*   columnas -> nivel + código + nombre.
*
* POR QUÉ ASÍ
*   Los nombres NO los escribimos a mano: se los pedimos a las
*   etiquetas que ya trae la base (con `decode`). Así, si mañana
*   cambia un código o una etiqueta en 01_privaciones, esto se
*   actualiza solo y no queda desincronizado.
*
* POR QUÉ VOLVEMOS A ABRIR LA BASE DE PRIVACIONES
*   Porque el microdato que guarda `mpitb est` conserva los códigos
*   pero no las etiquetas de area/prov/cities. La base original sí las
*   tiene, así que la abrimos de nuevo (una vez por cada corte). Es
*   más repetitivo, pero es la forma más simple y a prueba de errores.
*
* QUÉ ES UN `tempfile`
*   Una hoja de papel borrador: Stata la usa mientras corre el
*   do-file y la bota sola al terminar. Aquí usamos cuatro: una por
*   cada corte del país y una para el diccionario completo.
*-------------------------------------------------------------------
tempfile dic_area dic_prov dic_cities diccionario

* --- (a) Diccionario del corte "area" (urbano / rural) -------------
use "${gdStata}/Data Clean $MPM/DataDeprivations${MPM}.dta", clear
rename cod_CV_CP area           // el mismo apodo del PASO 8
keep area                       // solo necesitamos esta columna
duplicates drop                 // una fila por valor distinto: 1 y 2
decode area, gen(subg_name)     // el nombre que hay detrás del código
gen loa  = "area"               // a qué nivel pertenece esta traducción
gen subg = area                 // el código, con el nombre que usa mpitb
keep loa subg subg_name         // la libretita: 3 columnas
save `dic_area'

* --- (b) Diccionario del corte "prov" (las 7 provincias) -----------
use "${gdStata}/Data Clean $MPM/DataDeprivations${MPM}.dta", clear
rename cod_provincia prov
keep prov
duplicates drop
decode prov, gen(subg_name)
gen loa  = "prov"
gen subg = prov
keep loa subg subg_name
save `dic_prov'

* --- (c) Diccionario del corte "cities" (Malabo / urbano / rural) --
use "${gdStata}/Data Clean $MPM/DataDeprivations${MPM}.dta", clear
keep cities
duplicates drop
decode cities, gen(subg_name)
gen loa  = "cities"
gen subg = cities
keep loa subg subg_name
save `dic_cities'

* --- (d) Pegar las tres libretitas, una debajo de otra -------------
* `append using` = "pégame estas filas al final de las que ya tengo".
use `dic_area', clear
append using `dic_prov'
append using `dic_cities'

* --- (e) Agregar la fila del total nacional ------------------------
* El nivel "nat" no tiene subgrupos, así que le asignamos el código 0
* (es la misma convención que usa después 04_exportar_figuras.do).
*   `set obs`  = agrega una fila vacía al final
*   `in L`     = "en la última fila" (L de Last)
set obs `=_N + 1'
replace loa       = "nat"      in L
replace subg      = 0          in L
replace subg_name = "Nacional" in L

save `diccionario'


*-------------------------------------------------------------------
* PASO 14 | Pegar los nombres a los resultados y guardarlos
*-------------------------------------------------------------------
* IDEA SIMPLE
*   Abrimos la tabla de resultados y le pegamos, al lado de cada fila,
*   el nombre del subgrupo que le corresponde, usando la libretita del
*   paso anterior.
*
* EL CÓDIGO
*   `merge m:1 loa subg using ...`
*     merge  = pegar dos bases usando una llave común
*     m:1    = "muchos a uno": en los resultados hay MUCHAS filas por
*              subgrupo (una por medida, por indicador...), pero en la
*              libretita hay UNA sola fila por subgrupo
*     loa subg = la llave: para saber de quién hablamos hay que mirar
*              las dos columnas a la vez (ver PASO 13)
*     nogenerate = no dejes la variable de control _merge
*-------------------------------------------------------------------
use "${gdStata}/${MPM}_results.dta", clear

merge m:1 loa subg using `diccionario', nogenerate

label var subg_name "Nombre del subgrupo (según loa: area/prov/cities/nat)"

* Ordenamos siempre igual, para que 04_exportar_figuras.do lea las
* filas en un orden estable.
sort measure loa subg

save "${gdStata}/${MPM}_results.dta", replace


*-------------------------------------------------------------------
* PASO 15 | Marcar en el microdato quién es pobre multidimensional
*-------------------------------------------------------------------
* IDEA SIMPLE
*   Además de la tabla de resultados, queremos el listado de hogares
*   con una marca: pobre multidimensional sí / no. Es lo que después
*   permite cruzar la pobreza con cualquier otra variable del hogar.
*
* DE DÓNDE SALE c_equal
*   La creó `mpitb est` al pasarle la opción dtasave(): es el puntaje
*   de privación ponderado del hogar, el c_i del PASO C del mapa
*   inicial. Se llama "c" por el c_i del artículo, y "equal" por el
*   esquema de pesos que usamos.
*
* LA REGLA (PASO D del mapa inicial)
*   poor_multi = 1 si c_equal >= 1/3   (el mismo k = 33 del PASO 11)
*   poor_multi = 0 en caso contrario
*
* EL CÓDIGO
*   `gen poor_multi = (c_equal >= 1/3)` -> el paréntesis es una
*   pregunta de sí/no: Stata escribe 1 cuando es verdad y 0 cuando no.
*-------------------------------------------------------------------
use "${gdStata}/${MPM}_results_microdata.dta", clear

* Nos quedamos con lo que necesitan 04_exportar_figuras.do y
* 05_tabla_PEA_curso.do (incluidos c_equal, hhweight y strata).
keep hhid prov weight_hh hhsize electricity imp_wat_rec imp_san_rec area cities ///
     pcexp_ppp provincia quintile asistencia_escolar educat7 e_com ///
     e_enr i_elec i_imps i_impw poor1 hhweight strata c_equal //welfare_ppp

gen poor_multi = (c_equal >= 1/3)
label var poor_multi "Pobre multidimensional (k = 33%)"

save "${gdStata}/${MPM}_results_microdata.dta", replace


*-------------------------------------------------------------------
* PASO 16 | Un chequeo final: M0 tiene que ser igual a H x A
*-------------------------------------------------------------------
* IDEA SIMPLE
*   Antes de irnos, revisamos la cuenta. Si M0 no es igual a H por A,
*   algo se rompió en el camino.
*
* POR QUÉ
*   Es la identidad fundamental del método: M0 = H x A
*   (Suppa 2023, sección 2, p. 627).
*
* EL CÓDIGO
*   `summarize ..., meanonly` calcula el promedio en silencio; como
*   solo hay UNA fila que cumple la condición, ese promedio ES el
*   valor. `r(mean)` es donde Stata lo guarda, y con `scalar` lo
*   copiamos a una cajita con nombre para poder usarlo después.
*-------------------------------------------------------------------
use "${gdStata}/${MPM}_results.dta", clear

summarize b if measure == "H"  & loa == "nat" & k == 33, meanonly
scalar H_nat = r(mean)

summarize b if measure == "A"  & loa == "nat" & k == 33, meanonly
scalar A_nat = r(mean)

summarize b if measure == "M0" & loa == "nat" & k == 33, meanonly
scalar M0_nat = r(mean)

display as text _newline "==== RESULTADO NACIONAL (k = 33%) ===================="
display as text "  H  (incidencia) = " as result %6.4f H_nat ///
        as text "  ->  " as result %5.2f H_nat*100 as text "% de la poblacion es pobre multidimensional"
display as text "  A  (intensidad) = " as result %6.4f A_nat ///
        as text "  ->  los pobres sufren en promedio el " as result %5.2f A_nat*100 as text "% de las privaciones"
display as text "  M0 (el IPM)     = " as result %6.4f M0_nat
display as text "  Chequeo H x A   = " as result %6.4f H_nat*A_nat ///
        as text "  (debe coincidir con M0)"
display as text "======================================================" _newline


/*==================================================================
  PASO EXTRA (OPCIONAL) | Ejercicios tomados del artículo

  Todo lo de abajo NO hace falta para el pipeline: son ejercicios
  para entender mejor el método, tomados de los ejemplos 2, 3 y 4 de
  Suppa (2023, sección 4, pp. 646-650). Ninguno pisa los archivos
  oficiales: cada uno escribe su propio .dta.

  Para correrlos, cambia el 0 por un 1 en la línea de abajo.
==================================================================*/
global correr_extras 0

if $correr_extras == 1 {

    * Partimos del microdato que ya guardó mpitb: ahí están los 6
    * indicadores, el ponderador y el estrato. Volvemos a declarar el
    * diseño muestral y la receta porque estamos abriendo la base de
    * cero.
    *
    * OJO: en estos ejercicios `mpitb est` lleva la opción `replace`.
    * Es porque el microdato ya trae la variable c_equal (la fabricó
    * la corrida oficial del PASO 11) y mpitb la volvería a crear. Con
    * `replace` le decimos: "si ya existe, sobreescríbela"
    * (Suppa 2023, sección 3.2.5, p. 632).

    *---------------------------------------------------------------
    * EXTRA 1 | Sensibilidad al corte k (Suppa 2023, ejemplo 2)
    *---------------------------------------------------------------
    * PREGUNTA: si en vez de exigir 33% de privaciones exigiéramos
    * 20% o 50%, ¿cambiaría mucho la historia?
    * Con klist(...) se piden varios cortes de una sola vez. Nota que
    * pedimos solo measures(all), sin las medidas por indicador, para
    * no multiplicar por miles el número de estimaciones (esa es
    * justamente la lección del ejemplo 2 del artículo).
    use "${gdStata}/${MPM}_results_microdata.dta", clear
    svyset hhid [iw = hhweight], clear strata(strata)
    mpitb set, name(GNQ) ///
        d1(e_com e_enr,          name(educ))  ///
        d2(i_elec i_imps i_impw, name(infra)) ///
        d3(poor1,                name(mon))   ///
        replace

    mpitb est, name(GNQ) ///
        klist(20 33 50) ///
        weights(equal) ///
        measures(all) ///
        svy ///
        replace ///
        lsave("${gdStata}/${MPM}_extra1_varios_k.dta", replace)

    use "${gdStata}/${MPM}_extra1_varios_k.dta", clear
    sort measure k
    list measure k b se if loa == "nat", noobs sepby(measure)
    * Se espera: a mayor k, menos gente pobre (H baja) pero los que
    * quedan son más pobres (A sube).

    *---------------------------------------------------------------
    * EXTRA 2 | Otros pesos por dimensión (Suppa 2023, ejemplo 3)
    *---------------------------------------------------------------
    * PREGUNTA: ¿cuánto cambia el IPM si la dimensión monetaria pesara
    * la mitad (50%) y las otras dos un 25% cada una?
    * dimw() da los pesos por dimensión EN EL ORDEN de mpitb set
    * (d1 educ, d2 infra, d3 mon) y tienen que sumar 1.
    * name() es obligatorio para poder distinguirlos después.
    use "${gdStata}/${MPM}_results_microdata.dta", clear
    svyset hhid [iw = hhweight], clear strata(strata)
    mpitb set, name(GNQ) ///
        d1(e_com e_enr,          name(educ))  ///
        d2(i_elec i_imps i_impw, name(infra)) ///
        d3(poor1,                name(mon))   ///
        replace

    mpitb est, name(GNQ) ///
        klist(33) ///
        weights(dimw(.25 .25 .5) name(mon50)) ///
        measures(all) ///
        svy ///
        replace ///
        lsave("${gdStata}/${MPM}_extra2_pesos_mon50.dta", replace)

    use "${gdStata}/${MPM}_extra2_pesos_mon50.dta", clear
    list measure wgts b se if loa == "nat" & k == 33, noobs

    *---------------------------------------------------------------
    * EXTRA 3 | Quitar un indicador (Suppa 2023, ejemplo 3)
    *---------------------------------------------------------------
    * PREGUNTA: ¿cuánto le debe el IPM al indicador de electricidad?
    * Escribimos una receta nueva ("GNQ2") sin i_elec y comparamos.
    use "${gdStata}/${MPM}_results_microdata.dta", clear
    svyset hhid [iw = hhweight], clear strata(strata)

    mpitb set, name(GNQ2) ///
        d1(e_com e_enr,   name(educ))  ///
        d2(i_imps i_impw, name(infra)) ///
        d3(poor1,         name(mon))   ///
        description(sin electricidad) ///
        replace

    mpitb est, name(GNQ2) ///
        klist(33) ///
        weights(equal) ///
        measures(all) ///
        svy ///
        replace ///
        lsave("${gdStata}/${MPM}_extra3_sin_elec.dta", replace)

    use "${gdStata}/${MPM}_extra3_sin_elec.dta", clear
    list measure spec b se if loa == "nat" & k == 33, noobs

    *---------------------------------------------------------------
    * EXTRA 4 | Qué tanto se repiten los indicadores entre sí
    *           (mpitb assoc; Suppa 2023, sección 3.11)
    *---------------------------------------------------------------
    * PREGUNTA: ¿hay indicadores que dicen casi lo mismo? Si dos
    * indicadores siempre están privados en los mismos hogares,
    * estamos contando la misma carencia dos veces.
    *   R0 = medida de redundancia (cuánto se solapan)
    *   CV = V de Cramér (cuánto se asocian)
    * El comando imprime las dos matrices y además las deja guardadas
    * en r(R0) y r(CV) por si se quieren exportar.
    * Con depind() se listan los indicadores directamente, sin
    * necesidad de una receta guardada (Suppa 2023, sección 3.11).
    use "${gdStata}/${MPM}_results_microdata.dta", clear
    mpitb assoc, depind(e_com e_enr i_elec i_imps i_impw poor1)

    *---------------------------------------------------------------
    * EXTRA 5 | Cambios en el tiempo (Suppa 2023, ejemplo 4)
    *---------------------------------------------------------------
    * NO se puede correr con estos datos: tenemos una sola ronda de
    * encuesta. Se deja escrito para cuando haya dos.
    * La idea: se apilan las dos rondas en una sola base, se crea una
    * variable t (1 = primera ronda, 2 = segunda) y una variable con
    * el año, y `mpitb est` estima el cambio y si es significativo:
    *
    *   mpitb est, name(GNQ) klist(33) weights(equal) measures(all) ///
    *       svy tvar(t) cotyear(year) cotmeasures(M0 H A) ///
    *       cotoptions(total) ///
    *       lframe(niveles, replace) cotframe(cambios, replace)
    *
    *   tvar(t)        -> qué variable identifica la ronda
    *   cotyear(year)  -> el año, para anualizar el cambio
    *   cotmeasures()  -> de qué medidas quiero el cambio
    *   cotframe()     -> los cambios van en su propio frame, porque
    *                     una fila de cambio necesita columnas extra
    *                     (t0, t1, ann: inicio, fin y si está anualizado)

    display as text _newline "Ejercicios extra terminados. Archivos en: ${gdStata}"
}

* FIN DEL ARCHIVO --------------------------------------------------
