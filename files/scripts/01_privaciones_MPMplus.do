/*==================================================================
 PROYECTO:  IPM/MPM - QNG - Guinea Ecuatorial
 SCRIPT:    01_privaciones_MPMplus.do
 --------------------------------------------------------------------
 PROPÓSITO:
   Construir las variables BINARIAS de privación (0 = no privado, 1 = privado) para
   cada uno de los 6 indicadores del MPM, agrupados en 3 dimensiones:

     Dimensión 1 (Educación):        dep_educ_com, dep_educ_enr
     Dimensión 2 (Infraestructura):  dep_infra_elec, dep_infra_imps, dep_infra_impw
     Dimensión 3 (Monetaria):        dep_poor1

   Este script construye la variante MÁS EXIGENTE ("MPMplus"):
     - Umbral educativo: ESBA/secundaria (q3_05_grado_num>=11), adulto = 20+ años
       (con excepción para hogares jóvenes ya educados, ver más abajo).
     - Matrícula: además de la asistencia, penaliza el rezago escolar (2+ años).
     - Electricidad: además del acceso, penaliza los cortes del último mes.
     - Agua: excluye los pozos de la definición de fuente mejorada (salvo que
       el hogar haya tratado el agua).
     - Línea de pobreza monetaria: 8.30 USD PPA 2021.
==================================================================*/

* Versión más exigente del indicador de logro educativo: usa ESBA/secundaria
* básica en vez de primaria como mínimo logro para al menos un adulto del
* hogar. Se necesita una variable más detallada para ver ESBA: q3_05_grado.

*** Parámetros de la variante MPM+
  * Comentario: edades de corte usadas en los indicadores de educación
    global lbage 7       // Edad de inicio de primaria
    global ubage 14      // Se considera hasta 8vo grado (ESBA 2) como edad escolar
    global eduage 20     // ESBA/secundaria básica

*** Base individual de la encuesta de hogares
  use "$gdData/${database}", clear

***********************************************************
** PREPARACIÓN DE LA BASE 
***********************************************************

  ** Paso A — Muestra de análisis de pobreza (-> weight_hh_pov)
  /*
    La  base trae dos ponderadores de hogar:
      weight_hh      -> todos los hogares encuestados 
      weight_hh_pov  -> solo los hogares válidos para el análisis de pobreza 

    El MPM se calcula sobre la muestra de pobreza; por ello, se
    conservan los hogares que tienen weight_hh_pov y se utiliza ese
    ponderador en todo el pipeline.
  */
    // drop if missing(weight_hh_pov)

  ** Paso B — Variables geográficas (-> provincia, cod_CV_CP, rural, cities)
  /*
    cod_CV_CP distingue "Comunidad de vecinos" (1, zona urbana) de
    "Consejo de poblados" (2, zona rural). La variable original no se
    toca (ni el nombre ni la etiqueta): a partir de ella se crean rural
    y cities. Los nombres "Urban"/"Rural" que aparecen en los resultados
    se ponen en 03_calculo_mpm_mpitb.do (PASO 13).

    cities divide el país en tres áreas: Malabo (zona urbana de Bioko Norte,
    cod_provincia==2), resto urbano y rural.

    provincia (texto) se obtiene de las etiquetas de cod_provincia; la
    utiliza 05_tabla_PEA_curso.do para la tabla por provincia.
  */
    decode cod_provincia, gen(provincia)
    label var provincia "Provincia"

    gen rural = (cod_CV_CP==2) if !missing(cod_CV_CP)
    label var rural "Zona rural"

    gen cities = .
        replace cities = 1 if cod_CV_CP==1 & cod_provincia==2   // Malabo
        replace cities = 2 if cod_CV_CP==1 & cod_provincia!=2   // Resto urbano
        replace cities = 3 if cod_CV_CP==2                      // Rural
    label define cities 1 "Malabo" 2 "Other urban" 3 "Rural", replace
    label val cities cities
    label var cities "Área: Malabo, resto urbano, rural"

  ** Paso C — Quintiles de gasto per cápita (-> quintile)
  /*
    Quintiles de PERSONAS según pcexp_ppp: como la base es individual y
    cada persona lleva el peso de su hogar, cada quintil agrupa a ~20%
    de la población. Los usa 04_exportar_figuras.do (hoja "Dep by
    Quintile").
  */
    xtile quintile = pcexp_ppp [aw = weight_hh_pov], nq(5)
    label define quintile 1 "Quintile 1" 2 "Quintile 2" 3 "Quintile 3" 4 "Quintile 4" 5 "Quintile 5", replace
    label val quintile quintile
    label var quintile "Quintil de gasto per cápita (pcexp_ppp)"

* Identificador de hogar con el nombre que usa el resto del pipeline
* (mpitb, 03, 04 y 05). Se crea una copia (hhid) en vez de renombrar,
* para que interview__key quede tal como viene en la base.
  clonevar hhid = interview__key

***********************************************************
** Dimensión 1: Educación
***********************************************************

**# Logro educativo (Educational_attainment)
  ***********************************************************
  ** 1a) Indicador: Ningún adulto del hogar ha completado ESBA 4 /
  *                 secundaria básica.
  /*
    DESCRIPCIÓN GENERAL
    ───────────────────
    El indicador evalúa si en el hogar vive AL MENOS UNA persona
    adulta que haya alcanzado el nivel educativo exigido. Si ninguna lo
    alcanzó, el hogar entero se considera privado.

    Es un indicador de HOGAR construido a partir de información de
    PERSONAS: primero se evalúa a cada miembro por separado y después se
    resume el resultado para la vivienda. Una sola persona que cumpla es
    suficiente, porque se asume que su educación beneficia a todos los
    que conviven con ella.

    Lo único que distingue a este script de 01_privaciones_MPM.do en
    este indicador es el NIVEL EXIGIDO:

        MPM  (01_privaciones_MPM.do)  ->  Grado 6, primaria completa
        MPM+ (este script)            ->  ESBA 4, secundaria básica

    Como educat7 agrupa toda la secundaria en una sola categoría, aquí
    hace falta la variable con más detalle: q3_05_grado.

    EL NIVEL EXIGIDO EN LA ESCALA DEL CUESTIONARIO
    (q3_05_grado, pregunta 3.05: "¿Cuál es el grado educativo más alto
     que alcanzó?")
    ──────────────
    ┌────────┬────────────────────────────────────┬─────┬──────┐
    │ Código │ Grado más alto alcanzado           │ MPM │ MPM+ │
    ╞════════╪════════════════════════════════════╪═════╪══════╡
    │   0    │ Ninguno                            │  ✗  │  ✗   │
    │   1    │ Preescolar                         │  ✗  │  ✗   │
    │  2–6   │ Grados 1 a 5 (primaria)            │  ✗  │  ✗   │
    │   7    │ Grado 6 — primaria completa        │  ✓  │  ✗   │ <- nivel exigido por el MPM
    │   8    │ ESBA 1                             │  ✓  │  ✗   │
    │   9    │ ESBA 2                             │  ✓  │  ✗   │
    │  10    │ ESBA 3                             │  ✓  │  ✗   │
    │  11    │ ESBA 4 — secundaria básica         │  ✓  │  ✓   │ <- nivel exigido por el MPM+
    │ 12–13  │ Bachillerato 1 y 2                 │  ✓  │  ✓   │
    │ 14–15  │ Formación técnica básica/avanzada  │  ✓  │  ✓   │
    │ 16–19  │ Universidad, diplomado, posgrado   │  ✓  │  ✓   │
    └────────┴────────────────────────────────────┴─────┴──────┘
    ✓ = la persona alcanza el nivel    ✗ = no lo alcanza

    Por ello, el nivel exigido por el MPM+ se expresa directamente como
    q3_05_grado_num >= 11 (la versión numérica
    de q3_05_grado, creada en el PASO 0a).

    Quien nunca asistió a la escuela (pregunta 3.04 respondida "No…") no
    tiene grado registrado: q3_05_grado_num queda en missing y la condición
    no se cumple, que es el resultado correcto.

    CONDICIONES QUE DEBE CUMPLIR UNA PERSONA
    ────────────────────────────────────────
      1. Ser adulta: 20 años o más ($eduage)  ->  q1_03_edad  >= 20
      2. Haber alcanzado ESBA 4 o más         ->  q3_05_grado_num >= 11

    ¿Por qué 20 años y no 15 como en el MPM? Porque al elevar el nivel
    educativo exigido hay que elevar también la edad a la que resulta
    razonable exigirlo. Una persona que inicia primaria a los 7 años y
    no repite termina ESBA 4 en la adolescencia; a los 20 ya dispuso del
    tiempo necesario. Evaluar a alguien de 15 años frente al nivel
    ESBA 4 penalizaría al hogar por tener miembros que todavía están
    estudiando, no por su nivel educativo.

    PASO 1 — DE LAS PERSONAS AL HOGAR
    ─────────────────────────────────
      temp2 = 1 en cada PERSONA que cumple las dos condiciones
      temp3 = suma de temp2 dentro del hogar (hhid)
            = número de adultos del hogar que alcanzan el nivel exigido

        temp3 >= 1  ->  el hogar cuenta con al menos un adulto que
                        alcanza el nivel  ->  dep_educ_com = 0 (no privado)
        temp3 == 0  ->  ningún adulto lo alcanza
                                          ->  dep_educ_com = 1 (privado)

      NO se mide:  el nivel educativo promedio de los miembros del hogar.
      SÍ se mide:  si existe al menos un adulto que alcanza el nivel.

    Un hogar de seis personas donde cinco no terminaron primaria y una
    tiene bachillerato NO está privado: basta con esa persona.

    PASO 2 — EXCEPCIÓN PARA HOGARES SIN ADULTOS DE 20 AÑOS O MÁS
    ────────────────────────────────────────────────────────────
    Existe un caso que la regla anterior clasificaría mal: hogares donde
    no reside ninguna persona de 20 años o más, por ejemplo dos hermanos
    de 18 y 19 años que viven solos. Como nadie cumple la condición de
    edad, temp3 vale 0 y el hogar resulta privado por definición, aunque
    uno de ellos ya haya alcanzado ESBA 4. Se estaría midiendo la
    composición etaria del hogar y no su nivel educativo.

    La excepción corrige ese caso: si el hogar no tiene ningún miembro
    de 20 años o más (adults_count == 0) pero sí tiene exactamente una
    persona de 18 o 19 años con ESBA 4 o más (menores_ESBA_count == 1),
    se fuerza temp3 = 1 y el hogar queda clasificado como NO privado.

    ┌────────────────────────────────────┬──────────────┬────────────────┬──────────┐
    │ Hogar                              │ ¿Hay alguien │ ¿Alguien       │ dep_educ │
    │                                    │ de 20+ años? │ alcanza ESBA 4?│  _com    │
    ╞════════════════════════════════════╪══════════════╪════════════════╪══════════╡
    │ Padre 45 con Bach 2, 3 hijos       │ Sí           │ Sí (el padre)  │    0     │
    │ Madre 38 con Grado 6, 2 niños      │ Sí           │ No             │    1     │
    │ Hermanos 18 y 19, uno con ESBA 4   │ No           │ Sí, por PASO 2 │    0     │
    │ Hermanos 18 y 19, ninguno ESBA 4   │ No           │ No             │    1     │
    └────────────────────────────────────┴──────────────┴────────────────┴──────────┘

    PASO 3 — RESULTADO A NIVEL HOGAR
    ────────────────────────────────
    dep_educ_com = 1 únicamente si temp3 == 0 DESPUÉS de aplicar la
    excepción del PASO 2.
  */

  ** PASO 0a — Grado más alto alcanzado, de texto a código (3.05 -> q3_05_grado_num)
  * En la base q3_05_grado es texto, y `recode` solo sirve para variables
  * numéricas. Para texto se usa `encode`:
  *   1) label define: le asigna a cada respuesta, escrita EXACTAMENTE
  *      como viene en la base, su código 0-19 del cuestionario 
  *   2) encode: crea q3_05_grado_num (numérica) leyendo esa etiqueta. Sin
  *      label() los códigos saldrían en orden alfabético (Bach 1 = 1...).
  * La variable original (q3_05_grado, texto) se deja tal cual; la nueva
  * lleva el sufijo _num. Quien nunca fue a la escuela (3.04 = "No...")
  * tiene "" y queda en missing.
    label define grado_educ ///
        0  "Ninguno" ///
        1  "Pre-escolar" ///
        2  "Grado 1 (primaria ciclo 1)" ///
        3  "Grado 2 (primaria ciclo 1)" ///
        4  "Grado 3 (primaria ciclo 1)" ///
        5  "Grado 4 (primaria ciclo 2)" ///
        6  "Grado 5 (primaria ciclo 2)" ///
        7  "Grado 6 (primaria ciclo 2)" ///
        8  "ESBA 1 (Educacion Secundaria Basica)" ///
        9  "ESBA 2 (Educacion Secundaria Basica)" ///
        10 "ESBA 3 (Educacion Secundaria Basica)" ///
        11 "ESBA 4 (Educacion Secundaria Basica)" ///
        12 "Bach 1 (Bachillerato)" ///
        13 "Bach 2 (Bachillerato)" ///
        14 "Formación técnica y profesional básica" ///
        15 "Formación técnica y profesional avanzada" ///
        16 "Formación Universitaria (no egresado)" ///
        17 "Diplomado No universitario" ///
        18 "Graduado Universitario (Licenciado, Ingeniero, otro)" ///
        19 "Post grado (Maestria, PhD/ Doctorado)", replace
    encode q3_05_grado, gen(q3_05_grado_num) label(grado_educ) noextend
    label var q3_05_grado_num "Grado más alto alcanzado (3.05), código 0-19"

  ** PASO 0b — Nivel educativo en 7 categorías (3.04 + 3.05 -> educat7)
    * Nivel Educativo alcanzado 7 categorias
        gen educat7=.
        * Casos que nunca han estudiado
        replace educat7 = 1 if (inlist(q3_04_escuela,"No y tiene 20 años o menos de edad","No y es mayor de 20 años") | q3_04_escuela=="")
        * Casos según último grado cursado
        replace educat7 = 1 if inlist(q3_05_grado_num,0,1)
        replace educat7 = 2 if inlist(q3_05_grado_num,2,3,4,5,6)
        replace educat7 = 3 if inlist(q3_05_grado_num,7)
        replace educat7 = 4 if inlist(q3_05_grado_num,8,9,10,11,12,14)
        replace educat7 = 5 if inlist(q3_05_grado_num,13,15)
        replace educat7 = 6 if inlist(q3_05_grado_num,17)
        replace educat7 = 7 if inlist(q3_05_grado_num,16,18,19)

      label define educat7  1 "Ninguno" ///
                            2 "Primaria incompleta" ///
                            3 "Primaria completa" ///
                            4 "Secundaria incompleta" ///
                            5 "Secundaria completa" ///
                            6 "Post-secundaria pero no universidad" ///
                            7 "Universidad (finalizada o no)", replace
      label val educat7 educat7
      label var educat7 "Mayor nivel educación alcanzado (7 categorias)"

  ** PASO 1 — Personas que cumplen las dos condiciones (-> temp2, temp3)
    * temp2 = 1 si la persona es adulta (>=$eduage) y alcanzó ESBA/secundaria
    gen temp2 = 1 if q1_03_edad>=$eduage & q1_03_edad~=. & q3_05_grado_num>=11 & q3_05_grado_num~=.
    * temp3 = conteo de esos adultos por hogar (bys...egen sum: agregación
    * a nivel de grupo, ver explicación detallada en 01_limpieza_indicadores.do)
    bys hhid: egen temp3 = sum(temp2) // egen sum trata los missing como 0, así
                                       // que temp3 nunca es missing: temp3==0
                                       // significa "ningún adulto alcanza el nivel",
                                       // no "sin datos"

  ** PASO 2 — Excepción: hogares sin adultos de 20+ (-> temp3 forzado a 1)
    // Excepción (hogares jóvenes): si en el hogar no vive nadie
    // de 20+ años —así que temp3 no puede captar ningún adulto "formal"—
    // pero hay exactamente UNA persona de 18-19 años con ESBA 4 o más,
    // se fuerza temp3=1 y el hogar queda clasificado como NO privado.
    gen menores_ESBA = (q1_03_edad>=18 & q3_05_grado_num>=11 & q3_05_grado_num~=.)
    bys hhid: egen menores_ESBA_count = sum(menores_ESBA)
    gen check_adults = (q1_03_edad>=$eduage)
    bys hhid: egen adults_count = sum(check_adults)
    replace temp3 = 1 if menores_ESBA_count==1 & adults_count==0
        drop menores_ESBA menores_ESBA_count check_adults adults_count

  ** PASO 3 — Resultado a nivel hogar (-> dep_educ_com)
    gen dep_educ_com = 0
    replace dep_educ_com = 1 if temp3==0

    drop temp2 temp3 // variables temporales de conteo, ya no se necesitan
    la var dep_educ_com "MPM+: Privado si el hogar NO tiene adultos $eduage+ con secundaria completa"

  ****************************************************
  **1b) Indicador: niño/a en edad escolar no matriculado o con rezago
  /*
    El indicador evalúa si en el hogar vive AL MENOS UN niño o niña
    en edad escolar cuya trayectoria educativa no es la esperada. Si
    existe uno solo, el hogar entero se considera privado.

    De nuevo se parte de PERSONAS y se resume en el HOGAR, pero la
    lógica es la inversa a la del logro educativo: en aquel indicador
    bastaba con que una persona cumpliera la condición para que el hogar
    no estuviera privado; en este, basta con que un niño o niña no la
    cumpla para que el hogar quede privado.

        Logro educativo  ->  privado si NINGUNA persona adulta cumple
        Matrícula        ->  privado si ALGÚN niño o niña no cumple

    * QUÉ CAMBIA FRENTE AL MPM ESTÁNDAR
    El MPM estándar (01_privaciones_MPM.do) solo considera si el niño
    está matriculado. El MPM+ añade una segunda causa de privación: estar
    matriculado, pero cursando un grado muy por debajo del que
    correspondería a su edad.

        MPM   ->  no cumple quien NO está matriculado
        MPM+  ->  no cumple quien no está matriculado
                  O quien está matriculado con 2 o más años de rezago

    La razón es que la matrícula por sí sola puede ocultar problemas:
    un niño de 12 años inscrito en Grado 2 está en la escuela, pero su
    trayectoria educativa está claramente comprometida.

    * LAS DOS PREGUNTAS DEL CUESTIONARIO QUE SE USAN
    (3.08) "¿Asiste o asistió [Nombre] a una escuela o institución
           educativa durante el año escolar 2021-2022?"  ->  q3_08_asistio
           De aquí sale asistencia_escolar (1 = Sí, 0 = No).

    (3.11) "¿A qué grado asiste o asistió en el periodo 2021-2022?"
           ->  q3_11_gradoAsistido
           De aquí sale el rezago, comparando el grado que cursa con la
           edad que correspondería a ese grado.

    * ¿CÓMO SE CALCULA EL REZAGO?
    Primero se reconstruye la edad que tenía el niño AL EMPEZAR el año
    escolar 2021-2022, que es un año menos que la edad declarada en la
    encuesta:

        edad_n = q1_03_edad - 1

    Después se compara esa edad con la edad teórica del grado que cursa.
    En Guinea Ecuatorial la primaria empieza a los 7 años con el Grado 1,
    de modo que cada grado tiene una edad esperada:

    ┌──────────────────────────────────────┬──────────────┐
    │ Grado que cursa (3.11)               │ Edad teórica │
    ╞══════════════════════════════════════╪══════════════╡
    │ Pre-escolar                          │       6      │
    │ Grado 1 (primaria ciclo 1)           │       7      │
    │ Grado 2 (primaria ciclo 1)           │       8      │
    │ Grado 3 (primaria ciclo 1)           │       9      │
    │ Grado 4 (primaria ciclo 2)           │      10      │
    │ Grado 5 (primaria ciclo 2)           │      11      │
    │ Grado 6 (primaria ciclo 2)           │      12      │
    │ ESBA 1                               │      13      │
    │ ESBA 2                               │      14      │
    │ ESBA 3                               │      15      │
    │ ESBA 4                               │      16      │
    │ Bach 1                               │      17      │
    │ Bach 2                               │      18      │
    └──────────────────────────────────────┴──────────────┘

        rezago = edad_n - edad teórica del grado que cursa

    Un niño que va adelantado daría rezago negativo; eso no es una
    privación, por lo que se reemplaza por cero (replace rezago = 0 if rezago < 0).

    Finalmente se marca el rezago relevante:

        rezago_escolar = (rezago > 1)   es decir, 2 años o más de atraso

    El umbral no es "un año" sino "dos", porque edad_n es una
    aproximación y un año de diferencia puede deberse simplemente al mes
    de nacimiento o a un ingreso tardío. Con dos años ya se trata de un
    atraso sistemático.

    ┌────────────────────────────┬────────┬───────────┬────────┬──────────┐
    │ Niño/a                     │ edad_n │ E. teórica│ rezago │ ¿Privado?│
    ╞════════════════════════════╪════════╪═══════════╪════════╪══════════╡
    │  9 años, Grado 3           │    8   │      9    │   -1→0 │ No       │
    │ 10 años, Grado 3           │    9   │      9    │    0   │ No       │
    │ 11 años, Grado 3           │   10   │      9    │    1   │ No       │
    │ 12 años, Grado 3           │   11   │      9    │    2   │ Sí       │
    │ 11 años, Grado 2           │   10   │      8    │    2   │ Sí       │
    │ 13 años, no matriculado    │    –   │      –    │    –   │ Sí       │
    └────────────────────────────┴────────┴───────────┴────────┴──────────┘

    * PASO 1 — UNIVERSO: NIÑOS Y NIÑAS EN EDAD ESCOLAR
      temp2a        = 1 en cada niño/a de $lbage (7) a $ubage (14) años
      educ_enr_size = suma de temp2a por hogar
                    = número de niños/as en edad escolar del hogar

    Este conteo existe para poder distinguir dos situaciones que de otro
    modo se confundirían: un hogar SIN niños en edad escolar y un hogar
    CON niños que cumplen todos la condición. En ninguno de los dos
    casos habrá un niño en situación de privación, pero solo el segundo
    corresponde propiamente a un hogar "no privado"; al primero, el
    indicador simplemente no le aplica (véase el
    PASO 3).

    * PASO 2 — ¿ESTÁ PRIVADO CADA NIÑO O NIÑA?
    Dentro del universo (7 a 14 años), un niño se considera privado por
    cualquiera de estas dos causas:

      1. No está matriculado:  asistencia_escolar == 0
      2. Está matriculado pero con rezago:
                               asistencia_escolar == 1 & rezago_escolar == 1

      temp2 = 1 en cada niño/a privado/a por cualquiera de las dos causas
      temp3 = suma de temp2 por hogar
            = número de niños/as del hogar en esa situación

    * PASO 3 — RESULTADO A NIVEL HOGAR
      temp3 > 0            ->  dep_educ_enr = 1 (privado)
      temp3 == 0           ->  dep_educ_enr = 0 (no privado)
      educ_enr_size == 0   ->  dep_educ_enr = 0 (el hogar no tiene niños
                               en edad escolar: el indicador no aplica y
                               se le asigna "no privado")

    Conviene tener presente que esa última línea es una decisión de
    medición, no un dato: al hogar sin niños se le asigna 0 porque el
    método necesita un valor para todos los hogares, no porque se haya
    verificado algo sobre él.

    * OBSERVACIÓN SOBRE LOS VALORES MISSING
    En Stata el missing (.) es mayor que cualquier número, de modo que
    la expresión (rezago > 1) devuelve 1 también cuando rezago es
    missing. Y rezago queda missing cuando q3_11_gradoAsistido no
    coincide exactamente con ninguna de las cadenas de la lista de
    arriba: respuesta vacía, categoría no contemplada o una diferencia
    de escritura o de tildes.

    Como la condición de rezago solo se evalúa en quienes están
    matriculados, el efecto práctico es que un niño matriculado cuyo
    grado no se pudo clasificar cuenta como privado. Conviene
    comprobar cuántos casos hay antes de dar el indicador por bueno:

      count if inrange(q1_03_edad,$lbage,$ubage) & asistencia_escolar==1 ///
               & missing(rezago)
  */

  ** PASO 0a — Asistencia escolar (3.08 -> asistencia_escolar)
    gen asistencia_escolar = (q3_08_asistio=="Sí")
    label define labelschool 0 "No" 1 "Yes", replace
    label val asistencia_escolar labelschool
    label var asistencia_escolar "Asistió a institución educativa 2021/2022"

  ** PASO 0b — Cálculo del rezago escolar (3.11 + edad -> rezago_escolar)
    * rezago: edad al empezar el año escolar (edad-1) menos la edad teórica
    * del grado que cursa. rezago_escolar marca 2 años o más.
  	gen edad_n = q1_03_edad-1
    
		gen rezago = (edad_n - 6) if q3_11_gradoAsistido == "Pre-escolar"
      replace rezago = (edad_n - 7) if q3_11_gradoAsistido == "Grado 1 (primaria ciclo 1)"
      replace rezago = (edad_n - 8) if q3_11_gradoAsistido == "Grado 2 (primaria ciclo 1)"
      replace rezago = (edad_n - 9) if q3_11_gradoAsistido == "Grado 3 (primaria ciclo 1)"
      replace rezago = (edad_n - 10) if q3_11_gradoAsistido == "Grado 4 (primaria ciclo 2)"
      replace rezago = (edad_n - 11) if q3_11_gradoAsistido == "Grado 5 (primaria ciclo 2)"
      replace rezago = (edad_n - 12) if q3_11_gradoAsistido == "Grado 6 (primaria ciclo 2)"
      replace rezago = (edad_n - 13) if q3_11_gradoAsistido == "ESBA 1 (Educacion Secundaria Basica)"
      replace rezago = (edad_n - 14) if q3_11_gradoAsistido == "ESBA 2 (Educacion Secundaria Basica)"
      replace rezago = (edad_n - 15) if q3_11_gradoAsistido == "ESBA 3 (Educacion Secundaria Basica)"
      replace rezago = (edad_n - 16) if q3_11_gradoAsistido == "ESBA 4 (Educacion Secundaria Basica)"
      replace rezago = (edad_n - 17) if q3_11_gradoAsistido == "Bach 1 (Bachillerato)"
      replace rezago = (edad_n - 18) if q3_11_gradoAsistido == "Bach 2 (Bachillerato)"
      replace rezago = 0 if rezago < 0
		
		gen rezago_escolar = (rezago>1)

  ** PASO 1 — Universo: niños y niñas en edad escolar (-> educ_enr_size)
    * Tamaño del grupo en edad escolar, por hogar (para distinguir
    * "hogar sin niños en edad escolar" de "hogar con niños, todos ok")
    gen temp2a = 1 if q1_03_edad>=$lbage & q1_03_edad<=$ubage
    bys hhid: egen educ_enr_size = sum(temp2a)

  ** PASO 2 — ¿Está privado cada niño o niña? (-> temp2, temp3)
    * Privado si no está matriculado O si está matriculado con rezago
    gen temp2 = 1 if q1_03_edad>=$lbage & q1_03_edad<=$ubage & asistencia_escolar==0 // no matriculado
    replace temp2 = 1 if q1_03_edad>=$lbage & q1_03_edad<=$ubage & asistencia_escolar==1 & rezago_escolar==1 // matriculado con rezago
    bys hhid: egen temp3 = sum(temp2)

  ** PASO 3 — Resultado a nivel hogar (-> dep_educ_enr)
    gen dep_educ_enr = 0
    replace dep_educ_enr = 1 if temp3>0 & temp3~=.
    replace dep_educ_enr = 0 if educ_enr_size ==0 // hogar sin niños en edad escolar: no privado por este indicador

    drop temp2a temp2 temp3
    la var dep_educ_enr "MPM+: Privado si el hogar tiene al menos un niño/a en edad escolar no matriculado o con rezago"


****************************************************
** Dimensión 2: Acceso a infraestructura
****************************************************

**# Electricidad  
  ****************************************************
  /*
    El hogar está privado si no dispone de electricidad. El MPM+ añade
    una segunda forma de estar privado: disponer de electricidad pero
    sufrir cortes, porque tener la instalación no es lo mismo que tener
    servicio.

    A diferencia de los indicadores de educación, este no necesita
    resumir personas en hogares: el alumbrado se pregunta una sola vez
    para toda la vivienda, así que la respuesta ya viene a nivel de
    hogar.

    * QUÉ CAMBIA FRENTE AL MPM ESTÁNDAR

        MPM   ->  privado si el hogar NO tiene electricidad
        MPM+  ->  privado si no tiene electricidad
                  O si tuvo algún corte de luz en el último mes

    El MPM+ deja de medir solo el ACCESO y pasa a medir el SERVICIO.

    * PREGUNTA 2.31 — FUENTE DE ALUMBRADO DEL HOGAR
    "¿Cuál es la principal fuente de energía que se utiliza en este
     hogar para el alumbrado?"  ->  q2_31_energiaLuz

    ┌────────┬──────────────────────────────────────┬────────────────┐
    │ Código │ Fuente principal de alumbrado (2.31) │ ¿Electricidad? │
    ╞════════╪══════════════════════════════════════╪════════════════╡
    │ 1      │ Electricidad de la red pública       │ Sí             │
    │ 2      │ Placa solar                          │ Sí             │
    │ 3      │ Generador (gasolina)                 │ Sí             │
    │ 4      │ Generador (gasoil)                   │ Sí             │
    │ 5      │ Petróleo / keroseno                  │ No             │
    │ 6      │ Gas (lámpara)                        │ No             │
    │ 7      │ Batería / pila                       │ No             │
    │ 8      │ Vela                                 │ No             │
    │ 9      │ Leña                                 │ No             │
    │ 10     │ Otro                                 │ No             │
    └────────┴──────────────────────────────────────┴────────────────┘

    Las cuatro primeras opciones cuentan como electricidad y el resto no.
    Obsérvese que la red pública, la placa solar y el generador se tratan
    igual: lo que se mide es si la vivienda dispone de luz eléctrica, no
    de dónde viene ni con qué continuidad. Precisamente por eso el MPM+
    necesita una segunda pregunta.

    * PREGUNTA 2.33 — ¿CUÁNTOS DÍAS SE QUEDÓ SIN LUZ?
    "En el último mes ¿cuántos días se quedó el hogar sin energía
     eléctrica por más de 30 minutos?"  ->  q2_33_SinElect

    Solo se le formula a quien declaró tener electricidad en 2.31, y solo
    la responde quien efectivamente sufrió cortes: en los datos el valor
    mínimo registrado es 1 y no existe ningún 0. Por eso la condición del
    código puede escribirse como "tiene un valor" (q2_33_SinElect != .)
    en lugar de "tiene un valor mayor que cero".

    * PREGUNTAS QUE NO SE USAN
    (2.32)  ¿A quién le pagan por el servicio de electricidad?
            Solo define el recorrido del cuestionario: quién contesta
            2.32A y quién pasa directo a 2.33. No decide nada.
    (2.32A) ¿Cuánto fue el pago mensual? Descriptiva (FCFA).

    * CÓMO QUEDA CLASIFICADO CADA HOGAR

    ┌──────────────────────────────────┬──────────────┬──────────┬──────────┐
    │ Hogar                            │ Días sin luz │ MPM      │ MPM+     │
    │                                  │ (2.33)       │          │          │
    ╞══════════════════════════════════╪══════════════╪══════════╪══════════╡
    │ Red pública, sin cortes          │ ninguno      │ 0        │ 0        │
    │ Red pública, 2 días sin luz      │ 2            │ 0        │ 1        │
    │ Placa solar, 15 días sin luz     │ 15           │ 0        │ 1        │
    │ Alumbrado con vela               │ no aplica    │ 1        │ 1        │
    └──────────────────────────────────┴──────────────┴──────────┴──────────┘

    El efecto de la regla del MPM+ es grande: en la muestra del curso
    (2 702 registros individuales, sin ponderar) la privación por
    electricidad pasa de un 17 % a un 60 % aproximadamente. No es un
    error, es la consecuencia de medir servicio en vez de acceso: la
    mayoría de los hogares conectados reportó al menos un corte.

    * NOTA DE MANTENIMIENTO
    La condición q2_33_SinElect != . funciona porque en esta ronda el
    valor 0 nunca se registra. Si en una ronda futura se codificara 0
    para "ningún corte", esa condición marcaría como privado a TODO
    hogar con electricidad. La forma que no depende de ese supuesto es:

      replace dep_infra_elec = 1 if electricity==1 & q2_33_SinElect > 0 ///
                                    & !missing(q2_33_SinElect)
  */

  ** PASO 1 — Acceso a electricidad mejorado (2.31 -> electricity)
  * Igual que en el MPM. Códigos 1-4 = hay electricidad; 5-10 = no hay.
    gen electricity = inlist(q2_31_energiaLuz,1,2,3,4) if !missing(q2_31_energiaLuz)
    label define electricity 0 "Sin electricidad mejorada" 1 "Con electricidad mejorada", replace
    label val electricity electricity
    label var electricity "Hogar con acceso a electricidad. Recodificado de 2.31 (q2_31_energiaLuz)"

  ** PASO 2 — Indicador de privación, variante MPM (electricity -> dep_infra_elec)
    gen dep_infra_elec = (electricity==0) if electricity~=.
    la var dep_infra_elec "MPM: Privado si el hogar no tiene acceso a electricidad"

  ** PASO 3 — SOLO variante MPM+: penalizar corte de luz (2.33 -> dep_infra_elec)
    replace dep_infra_elec = 1 if electricity==1 & q2_33_SinElect!=.
    // aunque el hogar SÍ tenga electricidad, si reportó algún día sin luz
    // >30 min en el último mes, se reclasifica como Privado
    la var dep_infra_elec "MPM+: Privado si el hogar no tiene acceso a electricidad o tuvo corte de luz el último mes"

**# Saneamiento (saneamiento mejorado)
  ****************************************************
  /*
    El hogar tiene saneamiento mejorado solo si cumple DOS condiciones
    a la vez: que su instalación separe higiénicamente las excretas y
    que sea de uso exclusivo del hogar. Basta con no cumplir una de las
    dos para que el hogar quede privado.

        Condición 1 (tecnología)   ->  pregunta 2.28 (+ 2.28B / 2.28C)
        Condición 2 (exclusividad) ->  pregunta 2.29

    Esta es la definición estándar internacional (JMP de OMS-UNICEF, la
    misma que usa el GMD del Banco Mundial). La justificación de la
    segunda condición es sanitaria: un baño excelente compartido entre varias
    familias deja de cumplir su función.

    * ESTE INDICADOR NO CAMBIA ENTRE VARIANTES
    imp_san_rec es idéntico en el MPM y en el MPM+; el detalle de su
    construcción vive en la limpieza de la base y está documentado en
    01_privaciones_MPM.do. Lo único que hace este script es traducir esa
    variable en el indicador de privación:

        imp_san_rec == 1 (mejorado)     ->  dep_infra_imps = 0
        imp_san_rec == 0 (no mejorado)  ->  dep_infra_imps = 1

    Aun así, conviene conocer cómo se construye, porque el resultado
    depende de decisiones de medición que no son evidentes.

    * CONDICIÓN 1 — PREGUNTA 2.28: ¿QUÉ TIPO DE BAÑO USA EL HOGAR?

    ┌────────┬────────────────────────────────────┬────────────────────────────────┐
    │ Código │ Tipo de baño (2.28)                │ ¿Tecnología adecuada?          │
    ╞════════╪════════════════════════════════════╪════════════════════════════════╡
    │ 1      │ W.C. / inodoro                     │ Depende de 2.28B y 2.28C       │
    │ 2      │ Letrina                            │ Sí, siempre                    │
    │ 3      │ Hoyo áspero / agujero abierto      │ No                             │
    │ 4      │ Baño público                       │ No                             │
    │ 5      │ Sin baño (en la naturaleza)        │ No                             │
    │ 6      │ Otro                               │ No                             │
    └────────┴────────────────────────────────────┴────────────────────────────────┘

    Cuando la respuesta es W.C. (código 1) el cuestionario sigue
    preguntando cómo descarga, y cualquiera de las salidas posibles se
    acepta como adecuada:

        (2.28B) ¿Está conectado a una fuente de agua para descarga?
                  Sí                                   -> adecuado
                  No                                   -> se mira 2.28C
        (2.28C) ¿A dónde está conectado?  (solo si 2.28B = No)
                  1 Alcantarillado                     -> adecuado
                  2 Tubería que va al río o al mar     -> adecuado
                  3 Pozo ciego                         -> adecuado
                  sin respuesta o fuera de estos códigos -> missing

    Dos decisiones normativas que conviene conocer: toda LETRINA se
    acepta como adecuada sin mirar las preguntas 2.28D y 2.28E, que
    existen en el cuestionario pero no se usan; y el W.C. conectado a
    una tubería que desemboca en el río o el mar también se acepta,
    aunque desde el punto de vista ambiental sea discutible.

    * CONDICIÓN 2 — PREGUNTA 2.29: ¿EL BAÑO ES DE USO EXCLUSIVO DEL HOGAR?

    ┌────────┬────────────────────────────────────────┬────────────────────────┐
    │ Código │ Uso del baño (2.29)                    │ Efecto                 │
    ╞════════╪════════════════════════════════════════╪════════════════════════╡
    │ 1      │ Exclusivo del hogar                    │ Conserva condición 1   │
    │ 2      │ Compartido con otro hogar              │ Invalida condición 1   │
    │ 3      │ Compartido con varios hogares          │ Invalida condición 1   │
    │ 4      │ Otro                                   │ Invalida condición 1   │
    └────────┴────────────────────────────────────────┴────────────────────────┘

    * CÓMO QUEDA CLASIFICADO CADA HOGAR

    ┌────────────────────────────────┬────────────────┬──────────────┬──────────────┐
    │ Hogar                          │ Condición 1    │ Condición 2  │ dep_infra    │
    │                                │ (tecnología)   │ (exclusivo)  │ _imps        │
    ╞════════════════════════════════╪════════════════╪══════════════╪══════════════╡
    │ W.C. con descarga, exclusivo   │ Cumple         │ Cumple       │ 0            │
    │ W.C. con descarga, compartido  │ Cumple         │ No cumple    │ 1            │
    │ Letrina propia                 │ Cumple         │ Cumple       │ 0            │
    │ Hoyo abierto propio            │ No cumple      │ Cumple       │ 1            │
    │ Baño público                   │ No cumple      │ No cumple    │ 1            │
    └────────────────────────────────┴────────────────┴──────────────┴──────────────┘
  */
  ** PASO 0 — Construcción de imp_san_rec 
    **  Exclusividad del baño (2.29, texto -> toiletshared)
        * 1 = compartido (cualquier respuesta distinta de "Exclusivo del
        * Hogar"), 0 = exclusivo, missing si no hay respuesta.
        gen toiletshared = (q2_29_aseoExclusivo != "Exclusivo del Hogar") if q2_29_aseoExclusivo != ""
        label define toilet_exclusivo 1 "Toilet shared" 0 "Toilet exclusive", replace
        label val toiletshared toilet_exclusivo
        label var toiletshared "Baño compartido (1) vs exclusivo (0), recodificado de 2.29"

    **  Tipo de baño en 14 categorías (2.28 + 2.28B/2.28C -> toilet14)
        gen toilet14 = .
            replace toilet14 = 1  if q2_28_aseo==1 & q2_28B_fuente=="Sí"                                                          // WC conectado a agua
            replace toilet14 = 2  if q2_28_aseo==1 & q2_28B_fuente=="No" & ///
                                     inlist(q2_28C_conectado,"Sistema de alcantarillado","Conectado a tubería que va al rio/mar") // WC sin agua -> alcantarillado o río/mar
            replace toilet14 = 3  if q2_28_aseo==1 & q2_28B_fuente=="No" & q2_28C_conectado=="Conectado a pozo ciego"             // WC sin agua -> pozo ciego
            replace toilet14 = 5  if q2_28_aseo==2                                                                                // Letrina (cualquiera, no se mira 2.28D/2.28E)
            replace toilet14 = 10 if q2_28_aseo==3                                                                                // Hoyo áspero
            replace toilet14 = 8  if q2_28_aseo==4                                                                                // Baño público
            replace toilet14 = 13 if q2_28_aseo==5                                                                                // Sin baño
            replace toilet14 = 14 if q2_28_aseo==6                                                                                // Otro
        label var toilet14 "Tipo de baño, 14 categorías (recodificado de 2.28/2.28B/2.28C)"

    **  Colapso a 6 categorías (toilet14 -> toilet6)
        recode toilet14 (1/3=1) (5=2) (7=3) (6=4) (13=5) (else=9), gen(toilet6)
            replace toilet6=. if toilet14==.
        label var toilet6 "Tipo de baño, 6 categorías (recodificado de toilet14, siguiendo GMD)"

    **  Saneamiento mejorado (toilet6 + toiletshared -> imp_san_rec)
        recode toilet6 (1/4=1 "Improved sanitation") (nonmissing=0 "Not improved sanitation"), gen(imp_san_rec)
            replace imp_san_rec = 0 if toiletshared==1   // aunque la tecnología sea buena, si se comparte -> No mejorado
        label var imp_san_rec "Hogar con acceso a saneamiento mejorado (tecnología adecuada Y uso exclusivo)"

  ** PASO 1 — Indicador de privación (imp_san_rec -> dep_infra_imps)
      gen dep_infra_imps = (imp_san_rec==0) if imp_san_rec~=.
      la var dep_infra_imps "MPM+: Privado si el hogar no tiene acceso a saneamiento mejorado"

**# Agua mejorada
  ****************************************************
  /*
    El hogar está privado si el agua que usa no proviene de una fuente
    considerada segura. Igual que el alumbrado, se pregunta una sola vez
    para toda la vivienda, así que el dato ya viene a nivel de hogar.

    * QUÉ CAMBIA FRENTE AL MPM ESTÁNDAR
    El MPM+ es más exigente en un punto concreto: el POZO PÚBLICO deja
    de contar como fuente mejorada en todos los casos, también en zona
    urbana.

        MPM   ->  pozo público es mejorado si es urbano y no se trata el agua
        MPM+  ->  pozo público NUNCA es mejorado

    El pozo privado se trata igual en las dos variantes.

    * PREGUNTA 2.25 — FUENTE DE AGUA DEL HOGAR
    "¿De dónde obtienen principalmente el agua para todo uso las
     personas de este hogar?"  ->  q2_25_aguaTomar

    ┌────────┬──────────────────────────────────────┬────────────────┬────────────────┐
    │ Código │ Fuente principal de agua (2.25)      │ MPM            │ MPM+           │
    ╞════════╪══════════════════════════════════════╪════════════════╪════════════════╡
    │ 1      │ Grifo dentro de la vivienda          │ Mejorada       │ Mejorada       │
    │ 2      │ Grifo fuera de la vivienda           │ Mejorada       │ Mejorada       │
    │ 3      │ Grifo público                        │ Mejorada       │ Mejorada       │
    │ 4      │ Pozo público                         │ Depende        │ NUNCA          │
    │ 5      │ Pozo privado                         │ Depende        │ Depende        │
    │ 6      │ Río o lago                           │ No             │ No             │
    │ 7      │ Manantial                            │ No             │ No             │
    │ 8      │ Camión cisterna o tonel              │ No             │ No             │
    │ 9      │ Agua embotellada                     │ No             │ No             │
    │ 10     │ Otra vivienda / empresa              │ No             │ No             │
    │ 11     │ Otro                                 │ No             │ No             │
    └────────┴──────────────────────────────────────┴────────────────┴────────────────┘

    "Depende" significa que la respuesta por sí sola no decide: hay que
    mirar además la zona y el tratamiento del agua (ver más abajo).

    * REGLA CONTRAINTUITIVA: EL TRATAMIENTO DEL AGUA RECLASIFICA EL POZO
    Si un hogar que se abastece de un pozo declara que hierve, filtra o
    clora el agua, su fuente pasa a contar como NO mejorada. Leído sin
    contexto parece al revés —el hogar está haciendo lo correcto—, pero
    la lógica es otra: el tratamiento se interpreta como una señal de
    que el propio hogar no considera potable el agua de su pozo. La
    respuesta a 2.27 no se usa para premiar la conducta del hogar, sino
    como información sobre la calidad de la fuente.

    Esta regla se aplica SOLO a los pozos. Un hogar con grifo que
    también hierve el agua conserva su fuente como mejorada.

        (2.27) "En su casa ¿qué tratamiento le dan principalmente al
                agua para beber?"  ->  q2_27_tratamientoAgua
                "Ninguno"                              -> no se reclasifica
                La hierve / la filtran / le ponen lejía o cloro /
                beben agua embotellada / otro          -> el pozo se reclasifica

    * RESUMEN DE LOS DOS CASOS CON LÓGICA CONDICIONAL

    ┌──────────────────────┬──────────────┬──────────────┬──────────────────┬──────────────────┐
    │ Fuente               │ Zona         │ ¿Trata el    │ MPM              │ MPM+             │
    │                      │              │ agua? (2.27) │                  │                  │
    ╞══════════════════════╪══════════════╪══════════════╪══════════════════╪══════════════════╡
    │ Pozo público (4)     │ Urbana       │ No           │ Mejorada         │ No mejorada      │
    │ Pozo público (4)     │ Urbana       │ Sí           │ No mejorada      │ No mejorada      │
    │ Pozo público (4)     │ Rural        │ No o sí      │ No mejorada      │ No mejorada      │
    │ Pozo privado (5)     │ Cualquiera   │ No           │ Mejorada         │ Mejorada         │
    │ Pozo privado (5)     │ Cualquiera   │ Sí           │ No mejorada      │ No mejorada      │
    └──────────────────────┴──────────────┴──────────────┴──────────────────┴──────────────────┘

    En el MPM+ la columna de la zona ya no interviene: el pozo público
    queda excluido de entrada, en el propio recode (4 = 10), y el pozo
    privado solo depende del tratamiento.

    * CÓMO SE TRADUCE EN CÓDIGO
    Las 11 respuestas de 2.25 se transforman primero a la escala estándar de
    14 categorías del GMD (water14) y de ahí se resume en una variable
    binaria (imp_wat_rec). En esa escala, la categoría 5 es "pozo
    protegido" (cuenta como mejorada) y la 10 es "pozo no protegido"
    (no cuenta), de modo que reclasificar un pozo como no mejorado
    consiste en cambiar su código de 5 a 10.

        water14 entre 1 y 6, u 8   ->  imp_wat_rec = 1 (mejorada)
        cualquier otro valor       ->  imp_wat_rec = 0 (no mejorada)

    * NOTA SOBRE LOS VALORES MISSING
    q2_27_tratamientoAgua es una variable de texto, y la comparación
    != "Ninguno" también resulta verdadera cuando la respuesta está
    vacía (""). Es decir, un pozo sin respuesta en 2.27 se reclasificaría
    igual que uno tratado. En los datos de esta ronda no hay respuestas
    vacías, así que no afecta al resultado, pero conviene saberlo si el
    script se reutiliza con otra base.
  */
  ** PASO 1 — Fuente de agua en 14 categorías (2.25 -> water14)
      * Recategorización de la fuente de agua (14 categorías estándar).
      * Diferencia del MPM+: el pozo público (código 4 en 2.25) se asigna
      * directamente a la categoría 10 "pozo no protegido", de modo que
      * nunca cuenta como fuente mejorada. El pozo privado entra como 5
      * "pozo protegido" y solo se reclasifica si el hogar trata el agua
      * (ver el `replace` del PASO 2).
      recode q2_25_aguaTomar (1=1) (2=2) (3=3) (4=10) (5=5) (6=13) (7=9) (8=12) (9=7) (10=14) (11=14) (nonmissing= 0), gen(water14)

** PASO 2 — Excepción: pozo privado tratado (2.27 -> water14 = 10)
        * El pozo privado (código 5) se reclasifica como pozo NO protegido
        * (código 10) cuando el hogar declara CUALQUIER tratamiento del
        * agua distinto de "Ninguno": tratarla se lee como señal de que el
        * hogar no la considera potable.
        replace water14 = 10 if inlist(q2_25_aguaTomar, 5) & q2_27_tratamientoAgua!= "Ninguno"
        label var water14 "Fuente de agua: 14 categorías"
        label define water14 1 "Agua entubada dentro de la vivienda" 2 "Agua entubada al patio/parcela" 3 "Grifo o pilón público" 4 "Pozo entubado o perforado" 5 "Pozo protegido" 6 "Manantial protegido" 7 "Agua embotellada" 8 "Agua de lluvia" 9 "Manantial no protegido" 10 "Pozo no protegido" 11 "Carro con tanque/tambor pequeño" 12 "Camión cisterna" 13 "Agua superficial" 14  "Otro", replace
        label val water14 water14

  ** PASO 3 — Agua mejorada (water14 -> imp_wat_rec)
      * Mejorada = categorías 1 a 6 y 8; el resto, no mejorada.
      recode water14 (1/6 8=1 "Acceso a fuente de agua mejorada") (nonmissing=0 "Sin acceso a fuente de agua mejorada"), gen(imp_wat_rec)
      label var imp_wat_rec "Hogar con acceso a fuente de agua mejorada. Recodificada desde water14 siguiendo GMD. Igual a drinking_water"

  ** PASO 4 — Indicador de privación (imp_wat_rec -> dep_infra_impw)
      gen dep_infra_impw = (imp_wat_rec==0) if imp_wat_rec~=.
      la var dep_infra_impw "MPM+: Privado si el hogar no tiene acceso a agua potable mejorada (excluye pozo)"

****************************************************
** Dimensión 3: Monetaria
****************************************************
  /*
    * DESCRIPCIÓN GENERAL
    El hogar está privado si lo que gasta por persona y por día queda
    por debajo de una línea de pobreza internacional.

    * IMPLICACIONES DE QUE LA DIMENSIÓN TENGA UN SOLO INDICADOR
    Educación tiene dos indicadores e infraestructura tres, pero la
    dimensión monetaria tiene uno solo. Como cada dimensión pesa 1/3 y
    ese peso se reparte entre sus indicadores, en este caso el único
    indicador recibe la totalidad del peso de la dimensión (1/3):

        e_com, e_enr    ->  1/3 ÷ 2  =  1/6 cada uno
        i_elec, i_imps, i_impw  ->  1/3 ÷ 3  =  1/9 cada uno
        poor1           ->  1/3 ÷ 1  =  1/3

    Esto tiene una consecuencia importante: como el umbral de pobreza
    multidimensional es k = 1/3, un hogar por debajo de la línea
    monetaria alcanza el umbral con esa sola carencia y ya cuenta como
    pobre multidimensional, aunque no presente ninguna otra privación. El detalle
    está en 03_calculo_mpm.do.

    * QUÉ CAMBIA FRENTE AL MPM ESTÁNDAR
    Solo la altura de la línea:

        MPM   ->  3.00 USD PPA 2021  (pobreza extrema internacional)
        MPM+  ->  8.30 USD PPA 2021  (línea de países de ingreso
                                      medio-alto, el grupo al que
                                      pertenece Guinea Ecuatorial)

    ┌──────────────────────────────────┬────────────────┬────────────────┐
    │ Gasto diario por persona (PPA)   │ MPM (3.00)     │ MPM+ (8.30)    │
    ╞══════════════════════════════════╪════════════════╪════════════════╡
    │ 2.50 USD                         │ 1  privado     │ 1  privado     │
    │ 5.00 USD                         │ 0              │ 1  privado     │
    │ 8.29 USD                         │ 0              │ 1  privado     │
    │ 12.00 USD                        │ 0              │ 0              │
    └──────────────────────────────────┴────────────────┴────────────────┘

    * ORIGEN DE welfare_ppp
    La encuesta mide el gasto per cápita anual en francos CFA. Para
    poder compararlo con una línea internacional hay que traducirlo a
    dólares PPA por día, y eso es lo que hace la limpieza de la base:

        welfare_ppp = pcexp / ipc / ppp / 365
                      │       │     │     └─ de gasto anual a diario
                      │       │     └─────── 287.6907 FCFA = 1 USD PPA 2021
                      │       └───────────── 1.070633, lleva los precios
                      │                       al año base
                      └───────────────────── gasto per cápita anual (FCFA)

    En este script welfare_ppp solo se copia desde pcexp_ppp, que ya
    viene calculada; el cálculo de arriba se deja documentado porque es
    donde se decide en qué unidades está la línea de pobreza.
  */

  ** PASO 1 — Bienestar per cápita en dólares PPA por día (-> welfare_ppp)
    gen double welfare_ppp= pcexp_ppp

  ** PASO 2 — Indicador de privación (welfare_ppp -> dep_poor1)
    gen dep_poor1 = welfare_ppp< 8.30 if welfare_ppp~=.
    label var dep_poor1 "Pobreza monetaria internacional. Línea: 8.30 USD - PPA 2021"

    * `apoverty` también permite generar variables indicadoras de pobreza. En este caso se utiliza con la línea y el agregado de pobreza nacional
    apoverty GTpc_dr [aw = weight_hh_pov], varpl(zref) gen(monetary)

    save "${gdStata}/Data Clean $MPM/DataComplete_with_Deprivations.dta", replace


  * Recorte de variables: se conservan solo las necesarias para calcular
  * el IPM con `mpitb` (03_calculo_mpm_mpitb.do), evitando cargar toda la
  * base de la encuesta en ese paso.
    preserve
        keep hhid provincia cod_provincia cod_CV_CP q1_03_edad hhsize weight_hh_pov pcexp_ppp ///
            educat7 asistencia_escolar electricity imp_san_rec imp_wat_rec ///
            dep_educ_com educ_enr_size dep_educ_enr dep_infra_elec dep_infra_imps ///
            dep_infra_impw dep_poor1 quintile cities monetary1  //welfare_ppp (se conserva comentado: no se usa en el paso de mpitb pero podría ser útil para chequeos)
        save "${gdStata}/Data Clean $MPM/DataDeprivations${MPM}.dta", replace
    restore
