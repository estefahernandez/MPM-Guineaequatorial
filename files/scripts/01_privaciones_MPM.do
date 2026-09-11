/*==================================================================
 PROYECTO:      Medida de Pobreza Multidimensional (IPM / MPM)
                Guinea Ecuatorial (ENH2-2023)
 SCRIPT:        01_privaciones_MPM.do
 AUTOR ORIGINAL: Banco Mundial, proyecto GNQ-PA
 --------------------------------------------------------------------
 PROPÓSITO:
   Construir las variables BINARIAS de privación (0 = no privado, 1 = privado) para
   cada uno de los 6 indicadores del MPM, agrupados en 3 dimensiones:

     Dimensión 1 (Educación):        dep_educ_com, dep_educ_enr
     Dimensión 2 (Infraestructura):  dep_infra_elec, dep_infra_imps, dep_infra_impw
     Dimensión 3 (Monetaria):        dep_poor1

   Este script construye la variante ESTÁNDAR ("MPM"):
     - Umbral educativo: primaria completa (educat7>=3), adulto = 15+ años.
     - Matrícula: solo importa la asistencia escolar (sin penalizar rezago).
     - Electricidad: solo importa el acceso (no se penalizan los cortes).
     - Agua: se considera mejorada la fuente aunque sea un pozo protegido.
     - Línea de pobreza monetaria: 3.00 USD PPA 2021.
==================================================================*/

*** Parámetros de la variante MPM 
  * Comentario: edades de corte usadas en los indicadores de educación
    global lbage 7       // Edad de inicio de primaria
    global ubage 14      // Se considera hasta 8vo grado (ESBA 2) como edad escolar
    global eduage 15     // Edad mínima para considerar "adulto" en educación

*** Base individual de la encuesta de hogares
  use "$gdData/${database}", clear

* Simple renombre del identificador de hogar para usar en el comando pitb, etc
  ren interview__key hhid

***********************************************************
** Dimensión 1: Educación
***********************************************************

**# Logro educativo (Educational_attainment)
  ***********************************************************
  ** 1a) Indicador: ningún adulto del hogar ha completado la educación
  *                 primaria.
  /*
    * LA IDEA EN UNA FRASE
    El indicador se pregunta si en el hogar vive AL MENOS UNA persona
    adulta que haya completado la educación primaria. Si ninguna la
    completó, el hogar entero se considera privado.

    Es un indicador de HOGAR construido a partir de información de
    PERSONAS: primero se evalúa a cada miembro por separado y después se
    resume el resultado para la vivienda. Una sola persona que cumpla es
    suficiente, porque se asume que su educación beneficia a todos los
    que conviven con ella.

    * DOS CONDICIONES QUE DEBE CUMPLIR UNA PERSONA
      1. Ser adulta: 15 años o más ($eduage)  ->  q1_03_edad >= 15
      2. Haber completado primaria            ->  educat7    >= 3

    Las dos vienen de sitios distintos y conviene no confundirlas. La
    EDAD de 15 años sale del calendario escolar: quien entra a primaria
    a los 7 años y no repite, a los 15 ya ha tenido tiempo de sobra para
    terminarla (de hecho, debería ir por 9º grado). El NIVEL exigido, en
    cambio, es solo primaria completa. Es decir, los 15 años marcan a
    quién se le pregunta, y educat7 >= 3 marca qué se le exige.

    * EL NIVEL EXIGIDO EN LA ESCALA DEL CUESTIONARIO
    educat7 resume en 7 categorías las respuestas a las preguntas 3.04
    ("¿ha asistido alguna vez a la escuela?") y 3.05 ("¿cuál es el grado
    educativo más alto que alcanzó?"):

    ┌───────────┬──────────────────────────────────────┬──────────────────────────┬───────────┐
    │ educat7   │ Nivel alcanzado                      │ Códigos de 3.05          │ ¿Cumple?  │
    ╞═══════════╪══════════════════════════════════════╪══════════════════════════╪═══════════╡
    │ 1         │ Ninguno                              │ 0, 1 y "nunca estudió"   │ ✗         │
    │ 2         │ Primaria incompleta                  │ 2 a 6 (Grados 1 a 5)     │ ✗         │
    │ 3         │ Primaria completa                    │ 7 (Grado 6)              │ ✓         │
    │ 4         │ Secundaria incompleta                │ 8 a 12, 14               │ ✓         │
    │ 5         │ Secundaria completa                  │ 13, 15                   │ ✓         │
    │ 6         │ Post-secundaria no univ.             │ 17                       │ ✓         │
    │ 7         │ Universidad                          │ 16, 18, 19               │ ✓         │
    └───────────┴──────────────────────────────────────┴──────────────────────────┴───────────┘

    ✓ = la persona cumple el nivel exigido    ✗ = no lo cumple

    El corte cae entre "primaria incompleta" y "primaria completa", que
    es justo lo que significa educat7 >= 3.

    * PASO 1 — DE LAS PERSONAS AL HOGAR
      temp2 = 1 en cada PERSONA que cumple las dos condiciones
      temp3 = suma de temp2 dentro del hogar (hhid)
            = número de adultos del hogar con primaria completa

        temp3 >= 1  ->  dep_educ_com = 0 (no privado)
        temp3 == 0  ->  dep_educ_com = 1 (privado)

      NO se mide:  el nivel educativo promedio de los miembros del hogar.
      SÍ se mide:  si existe al menos un adulto que cumple el nivel.

    * CÓMO QUEDA CLASIFICADO CADA HOGAR

    ┌────────────────────────────────────────────┬──────────────────┬──────────────┐
    │ Hogar                                      │ ¿Alguien de 15+  │ dep_educ     │
    │                                            │ con primaria?    │ _com         │
    ╞════════════════════════════════════════════╪══════════════════╪══════════════╡
    │ Padre 45 con Grado 6, 3 hijos pequeños     │ Sí               │ 0            │
    │ Madre 38 con Grado 4, 2 niños              │ No               │ 1            │
    │ Abuela 70 sin estudios, hijo 22 con ESBA 2 │ Sí               │ 0            │
    │ Persona sola de 30 sin estudios            │ No               │ 1            │
    │ Padres sin estudios, hija 16 con Grado 6   │ Sí               │ 0            │
    └────────────────────────────────────────────┴──────────────────┴──────────────┘

    El último caso muestra que la condición de edad se aplica a la
    persona, no al hogar: una hija de 16 años con primaria terminada ya
    es "adulta" a efectos de este indicador.

    * DIFERENCIA CON LA VARIANTE MPM+
    El MPM+ (01_privaciones_MPMplus.do) sube las dos varas a la vez:
    exige ESBA 4 en lugar de primaria, y adulto de 20 años en lugar de
    15. Además añade una excepción para hogares donde no vive nadie de
    20 años o más. Aquí no hace falta esa excepción, porque con el corte
    en 15 años prácticamente todos los hogares tienen a alguien evaluable.
  */

  * CÓMO SE CONSTRUYE educat7 (no se hace aquí, viene de la limpieza de
  * la base; se reproduce para poder seguir el rastro hasta las preguntas)
  /*
    * Nivel Educativo alcanzado 7 categorias
        gen educat7=.
        * Casos que nunca han estudiado
        replace educat7 = 1 if (inlist(q3_04_escuela,"No y tiene 20 años o menos de edad","No y es mayor de 20 años") | q3_04_escuela=="") 
        * Casos según último grado cursado
        replace educat7 = 1 if inlist(q3_05_grado,0,1)
        replace educat7 = 2 if inlist(q3_05_grado,2,3,4,5,6)
        replace educat7 = 3 if inlist(q3_05_grado,7)
        replace educat7 = 4 if inlist(q3_05_grado,8,9,10,11,12,14)
        replace educat7 = 5 if inlist(q3_05_grado,13,15)
        replace educat7 = 6 if inlist(q3_05_grado,17)
        replace educat7 = 7 if inlist(q3_05_grado,16,18,19)
          
      label define educat7  1 "Ninguno" 
                            2 "Primaria incompleta" 
                            3 "Primaria completa" 
                            4 "Secundaria incompleta" 
                            5 "Secundaria completa" 
                            6 "Post-secundaria pero no universidad" 
                            7 "Universidad (finalizada o no)"
      label val educat7 educat7 
      label var educat7 "Mayor nivel educación alcanzado (7 categorias)"
  */

  ** PASO 1 — Personas que cumplen las dos condiciones (-> temp2, temp3)
    * temp2 = 1 si la persona es adulta (>=$eduage) y completó primaria
    gen temp2 = 1 if q1_03_edad>=$eduage & q1_03_edad~=. & educat7>=3 & educat7~=.

    * temp3 = conteo de esos adultos por hogar
    bys hhid: egen temp3 = sum(temp2) // egen sum trata los missing como 0, así
                                       // que temp3 nunca es missing: temp3==0
                                       // significa "ningún adulto completó
                                       // primaria", no "sin datos"

  ** PASO 2 — Resultado a nivel hogar (-> dep_educ_com)
    * El hogar está privado si NINGÚN adulto alcanza el nivel
    gen dep_educ_com = 0
    replace dep_educ_com = 1 if temp3==0

    drop temp2 temp3
    la var dep_educ_com "MPM: Privado si el hogar NO tiene adultos $eduage+ con primaria completa"

**# Matrícula escolar (Education_enrollment)
  ****************************************************
  ** 1b) Indicador: al menos un niño o niña en edad escolar no está
  *                 matriculado.
  /*
    * LA IDEA EN UNA FRASE
    El hogar está privado si tiene al menos un niño o niña de 7 a 14
    años que no asiste a la escuela.

    De nuevo se parte de PERSONAS y se resume en el HOGAR, pero la
    lógica es la contraria a la del logro educativo: allí bastaba una
    persona que cumpliera para salvar al hogar; aquí basta un niño o
    niña que falle para que el hogar quede privado.

        Logro educativo  ->  privado si NINGUNA persona adulta cumple
        Matrícula        ->  privado si ALGÚN niño o niña falla

    * LA PREGUNTA DEL CUESTIONARIO
    (3.08) "¿Asiste o asistió [Nombre] a una escuela o institución
           educativa durante el año escolar 2021-2022?" -> q3_08_asistio
           De aquí sale asistencia_escolar (1 = Sí, 0 = No).

    Una sola pregunta basta: en esta variante solo importa si el niño
    está o no en la escuela. El MPM+ añade una segunda forma de fallar
    —estar matriculado pero con dos o más años de rezago— usando además
    la pregunta 3.11.

    * QUÉ SIGNIFICA "EDAD ESCOLAR"
    De $lbage (7) a $ubage (14) años: desde el inicio de la primaria
    hasta ESBA 2, que corresponde a 8º grado. Fuera de ese rango el
    indicador no se aplica: un niño de 5 años sin matricular no hace
    que su hogar quede privado.

    * PASO 1 — UNIVERSO: NIÑOS Y NIÑAS EN EDAD ESCOLAR
      edad_escolar      = 1 en cada niño/a de 7 a 14 años
      cant_edadescolar  = suma por hogar = cuántos niños en edad escolar

    Este conteo existe para poder distinguir dos situaciones que de otro
    modo se confundirían: un hogar SIN niños en edad escolar y un hogar
    CON niños que están todos matriculados. En ambos casos no habrá
    ningún niño que falle, pero solo el segundo significa "no privado"
    por mérito propio; al primero, sencillamente, el indicador no le
    aplica (ver PASO 3).

    * PASO 2 — ¿FALLA CADA NIÑO O NIÑA?
      no_matriculado = 1 si está en edad escolar y no asiste
                     = . (missing) si está fuera de la edad escolar,
                       para que no cuente ni como privado ni como no
                       privado
      cant_no_matriculados = suma por hogar

    * PASO 3 — RESULTADO A NIVEL HOGAR
      cant_no_matriculados > 0  ->  dep_educ_enr = 1 (privado)
      cant_no_matriculados == 0 ->  dep_educ_enr = 0 (no privado)
      cant_edadescolar == 0     ->  dep_educ_enr = 0 (el hogar no tiene
                                    niños en edad escolar: el indicador
                                    no aplica y se le asigna "no privado")

    Conviene tener presente que esa última línea es una decisión de
    medición, no un dato: al hogar sin niños se le asigna 0 porque el
    método necesita un valor para todos los hogares, no porque se haya
    verificado algo sobre él.

    * CÓMO QUEDA CLASIFICADO CADA HOGAR

    ┌────────────────────────────────────────┬────────────────────┬────────────────┐
    │ Hogar                                  │ ¿Algún niño 7-14   │ dep_educ       │
    │                                        │ sin matricular?    │ _enr           │
    ╞════════════════════════════════════════╪════════════════════╪════════════════╡
    │ 2 niños de 8 y 11, ambos en la escuela │ No                 │ 0              │
    │ 2 niños de 8 y 11, uno sin matricular  │ Sí                 │ 1              │
    │ 1 niño de 13 sin matricular            │ Sí                 │ 1              │
    │ Solo adultos, sin niños de 7 a 14      │ No aplica          │ 0              │
    │ 1 niño de 5 sin matricular             │ No aplica          │ 0              │
    └────────────────────────────────────────┴────────────────────┴────────────────┘

    * NOTA SOBRE LOS VALORES MISSING
    La condición se escribe asistencia_escolar != 1, que también sería
    verdadera si la variable estuviera vacía. No ocurre: se construye
    como una comparación (q3_08_asistio == "Sí"), que siempre devuelve
    0 o 1. Por eso este script y el MPM+ —que escribe la condición
    equivalente asistencia_escolar == 0— dan exactamente el mismo
    resultado.

    Del mismo modo, cant_no_matriculados nunca es missing: egen sum
    trata los missing como 0, así que un hogar cuyos niños son todos
    missing en no_matriculado obtiene 0, no missing.
  */

  ** PASO 0 — Asistencia escolar (3.08 -> asistencia_escolar)
  * No se construye aquí, viene de la limpieza de la base:
    // gen asistencia_escolar = (q3_08_asistio=="Sí")
    // label var asistencia_escolar "Asistió a institución educativa 2021/2022"

  ** PASO 1 — Universo: niños y niñas en edad escolar (-> cant_edadescolar)
    * Definiendo los niños en "edad escolar" (entre $lbage y $ubage años)
    gen edad_escolar = (q1_03_edad>=$lbage & q1_03_edad<=$ubage)
    bys hhid: egen cant_edadescolar = sum(edad_escolar)

  ** PASO 2 — ¿Falla cada niño o niña? (-> no_matriculado, cant_no_matriculados)
    * No matriculado: está en edad escolar pero no asiste
    gen no_matriculado = (q1_03_edad>=$lbage & q1_03_edad<=$ubage & asistencia_escolar!=1)
        replace no_matriculado=. if q1_03_edad<$lbage | q1_03_edad>$ubage //asegurandose que si no esta en edad escolar no se le considere privado ni no privado, sino missing

    * Cantidad de niños no matriculados por hogar
    bys hhid: egen cant_no_matriculados = sum(no_matriculado)

  ** PASO 3 — Resultado a nivel hogar (-> dep_educ_enr)
    * El hogar está privado si tiene AL MENOS un niño/adolescente en edad
    * escolar que no está matriculado (por esto se calcula la suma, para detectar al menos uno).
    gen dep_educ_enr = 0
        replace dep_educ_enr = 1 if cant_no_matriculados>0 // cant_no_matriculados~=. nunca es missing por como se crea en el bysort 
        replace dep_educ_enr = 0 if cant_edadescolar==0 // hogares sin niños en edad escolar (universo de la privacion no estan en todos los hogares) no estan privados 

    drop edad_escolar no_matriculado cant_no_matriculados cant_edadescolar
    la var dep_educ_enr "MPM: Privado si el hogar tiene al menos un niño/a en edad escolar no matriculado"


****************************************************
** Dimensión 2: Acceso a infraestructura
****************************************************

**# Electricidad
  ****************************************************
  /*
    * LA IDEA EN UNA FRASE
    El hogar está privado si no dispone de electricidad para el
    alumbrado. Es el indicador más directo de los seis: una sola
    pregunta, sin condiciones encadenadas.

    A diferencia de los indicadores de educación, este no necesita
    resumir personas en hogares: el alumbrado se pregunta una sola vez
    para toda la vivienda, así que la respuesta ya viene a nivel de
    hogar.

    * LA PREGUNTA DEL CUESTIONARIO
    (2.31) "¿Cuál es la principal fuente de energía que se utiliza en
           este hogar para el alumbrado?"  ->  q2_31_energiaLuz

    ┌────────┬──────────────────────────────────────┬──────────────────┐
    │ Código │ Fuente principal de alumbrado (2.31) │ dep_infra_elec   │
    ╞════════╪══════════════════════════════════════╪══════════════════╡
    │ 1      │ Electricidad de la red pública       │ 0                │
    │ 2      │ Placa solar                          │ 0                │
    │ 3      │ Generador (gasolina)                 │ 0                │
    │ 4      │ Generador (gasoil)                   │ 0                │
    │ 5      │ Petróleo / keroseno                  │ 1                │
    │ 6      │ Gas (lámpara)                        │ 1                │
    │ 7      │ Batería / pila                       │ 1                │
    │ 8      │ Vela                                 │ 1                │
    │ 9      │ Leña                                 │ 1                │
    │ 10     │ Otro                                 │ 1                │
    └────────┴──────────────────────────────────────┴──────────────────┘

    Las cuatro primeras opciones cuentan como electricidad y el resto
    no. Obsérvese que la red pública, la placa solar y el generador se
    tratan igual: lo que se mide es si la vivienda dispone de luz
    eléctrica, no de dónde viene ni con qué continuidad.

    * DIFERENCIA CON LA VARIANTE MPM+
    Esa última frase es justo lo que el MPM+ considera insuficiente.
    Allí se añade la pregunta 2.33 (días sin luz en el último mes) y un
    hogar conectado pero con cortes también cuenta como privado:

        MPM   ->  mide el ACCESO    (¿hay instalación?)
        MPM+  ->  mide el SERVICIO  (¿hay luz de verdad?)

    El cambio no es menor: en la muestra del curso la privación por
    electricidad pasa de alrededor del 17 % con esta definición a cerca
    del 60 % con la del MPM+.
  */

  ** PASO 0 — Acceso a electricidad (2.31 -> electricity)
  * No se construye aquí, viene de la limpieza de la base:
    // gen electricity = (inlist(q2_31_energiaLuz,1,2,3,4))

  ** PASO 1 — Indicador de privación (electricity -> dep_infra_elec)
    gen dep_infra_elec = (electricity==0) if electricity~=.
    la var dep_infra_elec "Privado si el hogar no tiene acceso a electricidad"

**# Saneamiento (saneamiento mejorado)
  ****************************************************
  /*
    * LA IDEA EN UNA FRASE
    El hogar tiene saneamiento mejorado solo si aprueba DOS exámenes a
    la vez: que su instalación separe higiénicamente las excretas y que
    sea de uso exclusivo del hogar. Basta con fallar uno de los dos para
    quedar privado.

        Examen 1 (tecnología)   ->  pregunta 2.28 (+ 2.28B / 2.28C)
        Examen 2 (exclusividad) ->  pregunta 2.29

    Esta es la definición estándar internacional (JMP de OMS-UNICEF, la
    misma que usa el GMD del Banco Mundial). La lógica del segundo
    examen es sanitaria: un baño excelente compartido entre varias
    familias deja de cumplir su función.

    * ESTE INDICADOR NO CAMBIA ENTRE VARIANTES
    imp_san_rec es idéntico en el MPM y en el MPM+. De los cinco
    indicadores no monetarios, este es el único que las dos variantes
    comparten sin ninguna diferencia.

        imp_san_rec == 1 (mejorado)     ->  dep_infra_imps = 0
        imp_san_rec == 0 (no mejorado)  ->  dep_infra_imps = 1

    * EXAMEN 1 — PREGUNTA 2.28: ¿QUÉ TIPO DE BAÑO USA EL HOGAR?

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
                  Sí                                     -> adecuado
                  No                                     -> se mira 2.28C
        (2.28C) ¿A dónde está conectado?  (solo si 2.28B = No)
                  1 Alcantarillado                       -> adecuado
                  2 Tubería que va al río o al mar       -> adecuado
                  3 Pozo ciego                           -> adecuado
                  sin respuesta o fuera de estos códigos -> missing

    (2.28A) ¿El W.C. está dentro o fuera de la vivienda? Es descriptiva:
            no decide nada.

    Dos decisiones normativas que conviene conocer: toda LETRINA se
    acepta como adecuada sin mirar las preguntas 2.28D y 2.28E, que
    existen en el cuestionario pero no se usan; y el W.C. conectado a
    una tubería que desemboca en el río o el mar también se acepta,
    aunque desde el punto de vista ambiental sea discutible.

    * EXAMEN 2 — PREGUNTA 2.29: ¿EL BAÑO ES SOLO DEL HOGAR?

    ┌────────┬────────────────────────────────────────┬────────────────────────┐
    │ Código │ Uso del baño (2.29)                    │ Efecto                 │
    ╞════════╪════════════════════════════════════════╪════════════════════════╡
    │ 1      │ Exclusivo del hogar                    │ Mantiene el examen 1   │
    │ 2      │ Compartido con otro hogar              │ Anula el examen 1      │
    │ 3      │ Compartido con varios hogares          │ Anula el examen 1      │
    │ 4      │ Otro                                   │ Anula el examen 1      │
    └────────┴────────────────────────────────────────┴────────────────────────┘

    * CÓMO QUEDA CLASIFICADO CADA HOGAR

    ┌────────────────────────────────┬────────────────┬──────────────┬──────────────┐
    │ Hogar                          │ Examen 1       │ Examen 2     │ dep_infra    │
    │                                │ (tecnología)   │ (exclusivo)  │ _imps        │
    ╞════════════════════════════════╪════════════════╪══════════════╪══════════════╡
    │ W.C. con descarga, exclusivo   │ Aprueba        │ Aprueba      │ 0            │
    │ W.C. con descarga, compartido  │ Aprueba        │ Falla        │ 1            │
    │ Letrina propia                 │ Aprueba        │ Aprueba      │ 0            │
    │ Hoyo abierto propio            │ Falla          │ Aprueba      │ 1            │
    │ Baño público                   │ Falla          │ Falla        │ 1            │
    └────────────────────────────────┴────────────────┴──────────────┴──────────────┘

    * CÓMO SE TRADUCE EN CÓDIGO
    La construcción pasa por varias variables intermedias, que se
    reproducen más abajo tal como están en la limpieza de la base:

        toiletshared  (2.29)            ->  ¿el baño es compartido?
        toilet14      (2.28 + B + C)    ->  tipo de baño, escala GMD
        toilet6       (colapso de toilet14)
        imp_san_rec   (toilet6 + toiletshared)

    El examen 2 se aplica al final y tiene derecho de veto: la línea
    `replace imp_san_rec = 0 if toiletshared==1` anula un resultado
    favorable del examen 1.
  */

  ** CÓMO SE CONSTRUYE imp_san_rec (no se hace aquí, viene de la limpieza)
  /*
    **  Exclusividad del baño (2.29 -> toiletshared)
        recode q2_29_aseoExclusivo (2/4 = 1) (nonmissing = 0), gen(toiletshared)
        label define toilet_exclusivo 1 "Toilet shared" 0 "Toilet exclusive"
        label val toiletshared toilet_exclusivo
        label var toiletshared "Baño compartido (1) vs exclusivo (0), recodificado de 2.29"

    **  Tipo de baño en 14 categorías (2.28 + 2.28B/2.28C -> toilet14)
        gen toilet14 = .
            replace toilet14 = 1  if q2_28_aseo==1 & q2_28B_fuente==1                                   // WC conectado a agua
            replace toilet14 = 2  if q2_28_aseo==1 & q2_28B_fuente==2 & inlist(q2_28C_conectado,1,2)    // WC sin agua -> alcantarillado o río/mar
            replace toilet14 = 3  if q2_28_aseo==1 & q2_28B_fuente==2 & q2_28C_conectado==3             // WC sin agua -> pozo ciego
            replace toilet14 = 5  if q2_28_aseo==2                                                      // Letrina (cualquiera, no se mira 2.28D/2.28E)
            replace toilet14 = 10 if q2_28_aseo==3                                                      // Hoyo áspero
            replace toilet14 = 8  if q2_28_aseo==4                                                      // Baño público
            replace toilet14 = 13 if q2_28_aseo==5                                                      // Sin baño
            replace toilet14 = 14 if q2_28_aseo==6                                                      // Otro
        label var toilet14 "Tipo de baño, 14 categorías (recodificado de 2.28/2.28B/2.28C)"

    **  Colapso a 6 categorías (toilet14 -> toilet6)
        recode toilet14 (1/3=1) (5=2) (7=3) (6=4) (13=5) (else=9), gen(toilet6)
            replace toilet6=. if toilet14==.
        label var toilet6 "Tipo de baño, 6 categorías (recodificado de toilet14, siguiendo GMD)"

    **  Saneamiento mejorado (toilet6 + toiletshared -> imp_san_rec)
        recode toilet6 (1/4=1 "Improved sanitation") (nonmissing=0 "Not improved sanitation"), gen(imp_san_rec)
            replace imp_san_rec = 0 if toiletshared==1   // aunque la tecnología sea buena, si se comparte -> No mejorado
        label var imp_san_rec "Hogar con acceso a saneamiento mejorado (tecnología adecuada Y uso exclusivo)"

  */

  ** PASO 1 — Indicador de privación (imp_san_rec -> dep_infra_imps)
  gen dep_infra_imps = (imp_san_rec==0) if imp_san_rec~=.
  la var dep_infra_imps "MPM: Privado si el hogar no tiene acceso a saneamiento mejorado"

**# Agua mejorada
  ****************************************************
  /*
    * LA IDEA EN UNA FRASE
    El hogar está privado si el agua que usa no proviene de una fuente
    considerada segura. Igual que el alumbrado, se pregunta una sola vez
    para toda la vivienda, así que el dato ya viene a nivel de hogar.

    * LA PREGUNTA PRINCIPAL
    (2.25) "¿De dónde obtienen principalmente el agua para todo uso las
           personas de este hogar?"  ->  q2_25_aguaTomar

    ┌────────┬────────────────────────────────────────┬──────────────────────────┐
    │ Código │ Fuente principal de agua (2.25)        │ ¿Fuente mejorada?        │
    ╞════════╪════════════════════════════════════════╪══════════════════════════╡
    │ 1      │ Grifo dentro de la vivienda            │ Sí                       │
    │ 2      │ Grifo fuera de la vivienda             │ Sí                       │
    │ 3      │ Grifo público                          │ Sí                       │
    │ 4      │ Pozo público                           │ Depende (zona + 2.27)    │
    │ 5      │ Pozo privado                           │ Depende (2.27)           │
    │ 6      │ Río o lago                             │ No                       │
    │ 7      │ Manantial                              │ No                       │
    │ 8      │ Camión cisterna o tonel                │ No                       │
    │ 9      │ Agua embotellada                       │ No                       │
    │ 10     │ Otra vivienda / empresa                │ No                       │
    │ 11     │ Otro                                   │ No                       │
    └────────┴────────────────────────────────────────┴──────────────────────────┘

    Nueve de las once respuestas deciden por sí solas. Los dos pozos son
    los únicos casos con lógica condicional, y por eso se tratan aparte.

    * POR QUÉ EL MANANTIAL Y EL AGUA EMBOTELLADA NO CUENTAN
    Son dos exclusiones que suelen sorprender. El manantial queda fuera
    porque el cuestionario no distingue entre manantial protegido y no
    protegido, y ante la duda la definición estándar asume el caso
    desfavorable. El agua embotellada queda fuera porque el indicador
    mide el agua "para todo uso" del hogar —cocinar, lavarse—, no solo
    la de beber: quien compra botellas normalmente sigue usando otra
    fuente para lo demás.

    * LOS DOS POZOS: ZONA Y TRATAMIENTO
    Dos preguntas adicionales pueden degradar un pozo:

    (2.27) "En su casa ¿qué tratamiento le dan principalmente al agua
           para beber?"  ->  q2_27_tratamientoAgua
             "Ninguno"                                  -> no degrada
             La hierven / la filtran / le ponen lejía o cloro /
             beben agua embotellada / otro              -> degrada el pozo

    (rural) Zona del hogar, ya construida en la limpieza a partir de
            cod_CV_CP (1 = Urbano, 2 = Rural). Solo afecta al pozo
            público: en zona rural nunca cuenta como mejorado.

    ┌──────────────────────┬──────────────┬──────────────────┬────────────────────┐
    │ Fuente               │ Zona         │ ¿Trata el agua?  │ imp_wat_rec        │
    │                      │              │ (2.27)           │                    │
    ╞══════════════════════╪══════════════╪══════════════════╪════════════════════╡
    │ Pozo público (4)     │ Urbana       │ No               │ 1  Mejorada        │
    │ Pozo público (4)     │ Urbana       │ Sí               │ 0  No mejorada     │
    │ Pozo público (4)     │ Rural        │ No o sí          │ 0  No mejorada     │
    │ Pozo privado (5)     │ Cualquiera   │ No               │ 1  Mejorada        │
    │ Pozo privado (5)     │ Cualquiera   │ Sí               │ 0  No mejorada     │
    └──────────────────────┴──────────────┴──────────────────┴────────────────────┘

    * LA REGLA QUE SORPRENDE: TRATAR EL AGUA LA DEGRADA
    Si un hogar que se abastece de un pozo declara que hierve, filtra o
    clora el agua, su fuente pasa a contar como NO mejorada. Leído sin
    contexto parece al revés —el hogar está haciendo lo correcto—, pero
    la lógica es otra: el tratamiento se interpreta como una señal de
    que el propio hogar no considera potable el agua de su pozo. La
    respuesta a 2.27 no se usa para premiar la conducta del hogar, sino
    como información sobre la calidad de la fuente.

    Esta regla se aplica SOLO a los pozos. Un hogar con grifo que
    también hierve el agua conserva su fuente como mejorada.

    * PREGUNTA QUE NO SE USA
    (2.26) ¿A qué distancia está la fuente y cuánto se tarda en traer el
           agua? Descriptiva: no decide mejorada / no mejorada, aunque
           en otras metodologías el tiempo de acarreo sí cuenta.

    * CÓMO SE TRADUCE EN CÓDIGO
    Las 11 respuestas de 2.25 se llevan primero a la escala estándar de
    14 categorías del GMD (water14) y de ahí se resume en una variable
    binaria (imp_wat_rec). En esa escala la categoría 4 es "pozo público
    entubado" y la 5 "pozo protegido" (ambas cuentan como mejoradas),
    mientras que la 10 es "pozo no protegido" (no cuenta). Degradar un
    pozo consiste, literalmente, en reescribirlo como 10.

        water14 entre 1 y 6, u 8   ->  imp_wat_rec = 1 (mejorada)
        cualquier otro valor       ->  imp_wat_rec = 0 (no mejorada)

    * DIFERENCIA CON LA VARIANTE MPM+
    El MPM+ es más estricto en un punto: el pozo público deja de contar
    como mejorado en todos los casos, también en zona urbana. El pozo
    privado se trata igual en las dos variantes.

        MPM   ->  pozo público mejorado si es urbano y no se trata el agua
        MPM+  ->  pozo público NUNCA mejorado

    * NOTA SOBRE LOS VALORES MISSING
    q2_27_tratamientoAgua es una variable de texto, y la comparación
    != "Ninguno" también resulta verdadera cuando la respuesta está
    vacía (""). Es decir, un pozo sin respuesta en 2.27 se degradaría
    igual que uno tratado. En los datos de esta ronda no hay respuestas
    vacías, así que no afecta al resultado, pero conviene saberlo si el
    script se reutiliza con otra base.
  */

  ** CÓMO SE CONSTRUYE imp_wat_rec (no se hace aquí, viene de la limpieza)
  /*
    ** Fuente de agua en 14 categorías (2.25 -> water14)
        recode q2_25_aguaTomar (1=1) (2=2) (3=3) (4=4) (5=5) (6=13) (7=9) (8=12) (9=7) (10=14) (11=14) (nonmissing=0), gen(water14)
        label var water14 "Fuente de agua, 14 categorías (recodificado de 2.25)"
        label define water14    1 "Agua entubada dentro de la vivienda" ///
                                2 "Agua entubada al patio/parcela" ///
                                3 "Grifo o pilón público" ///
                                4 "Pozo entubado o perforado (público)" ////
                                5 "Pozo protegido (privado)" ///
                                6 "Manantial protegido" ///
                                7 "Agua embotellada" ///
                                8 "Agua de lluvia" ///
                                9 "Manantial no protegido" ///
                                10 "Pozo no protegido" ///
                                11 "Carro con tanque/tambor pequeño" ///
                                12 "Camión cisterna" ///
                                13 "Agua superficial" ///
                                14 "Otro", replace
        label val water14 water14

    ** Excepción rural para pozo público (rural + water14==4 -> degradar)
        replace water14 = 10 if water14==4 & rural==1
        // agua de pozo público se considera mejorada en zona urbana pero no mejorada en zona rural

    ** Excepción por tratamiento del agua (pozo público o privado -> degradar)
        replace water14 = 10 if inlist(q2_25_aguaTomar, 4,5) & q2_27_tratamientoAgua!= "Ninguno"
        // si el hogar SÍ trata el agua del pozo (la hierve, filtra, le pone cloro, etc.),
        // se reclasifica como No mejorada, sin importar zona urbana o rural

    ** Agua mejorada (water14 -> imp_wat_rec)
        recode water14 (1/6 8=1 "Access to improve water source") (nonmissing=0 "No access to improve water source"), gen(imp_wat_rec)
        label var imp_wat_rec "Hogar con acceso a fuente de agua mejorada. Recodificada desde water14 siguiendo GMD"

        clonevar drinking_water = imp_wat_rec
        label var drinking_water "Hogar con acceso a fuente de agua mejorada. Igual a imp_wat_rec"
  */

  ** PASO 1 — Indicador de privación (imp_wat_rec -> dep_infra_impw)
  gen dep_infra_impw = (imp_wat_rec==0) if imp_wat_rec~=.
  la var dep_infra_impw "MPM: Privado si el hogar no tiene acceso a agua potable mejorada"

****************************************************
** Dimensión 3: Monetaria
****************************************************
  /*
    * LA IDEA EN UNA FRASE
    El hogar está privado si lo que gasta por persona y por día queda
    por debajo de la línea de pobreza extrema internacional: 3.00 USD
    en paridad de poder adquisitivo (PPA) de 2021.

    * ESTA DIMENSIÓN TIENE UN SOLO INDICADOR, Y ESO IMPORTA
    Educación tiene dos indicadores e infraestructura tres, pero la
    dimensión monetaria tiene uno solo. Como cada dimensión pesa 1/3 y
    ese peso se reparte entre sus indicadores, aquí el único indicador
    se lleva el tercio entero:

        e_com, e_enr            ->  1/3 ÷ 2  =  1/6 cada uno
        i_elec, i_imps, i_impw  ->  1/3 ÷ 3  =  1/9 cada uno
        poor1                   ->  1/3 ÷ 1  =  1/3

    La consecuencia es fuerte: como el umbral de pobreza
    multidimensional es k = 1/3, un hogar por debajo de la línea
    monetaria alcanza el umbral con esa sola carencia y ya cuenta como
    pobre multidimensional, aunque no falle en nada más. El detalle
    está en 03_calculo_mpm.do.

    * DE DÓNDE SALE welfare_ppp
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

    * DIFERENCIA CON LA VARIANTE MPM+
    Solo la altura de la línea:

        MPM   ->  3.00 USD PPA 2021  (pobreza extrema internacional)
        MPM+  ->  8.30 USD PPA 2021  (línea de países de ingreso
                                      medio-alto, el grupo al que
                                      pertenece Guinea Ecuatorial)

    ┌──────────────────────────────────┬──────────────────┬──────────────────┐
    │ Gasto diario por persona (PPA)   │ MPM (3.00)       │ MPM+ (8.30)      │
    ╞══════════════════════════════════╪══════════════════╪══════════════════╡
    │ 2.50 USD                         │ 1  privado       │ 1  privado       │
    │ 5.00 USD                         │ 0                │ 1  privado       │
    │ 8.29 USD                         │ 0                │ 1  privado       │
    │ 12.00 USD                        │ 0                │ 0                │
    └──────────────────────────────────┴──────────────────┴──────────────────┘
  */

  ** PASO 0 — Factores de conversión (documentados; se aplican en la limpieza)
  /*
    gen ppp = 287.6907
    gen ipc = 1.070633

    gen welfare_ppp = pcexp/ipc/ppp/365
  */

  ** PASO 1 — Bienestar per cápita en dólares PPA por día (-> welfare_ppp)
        gen welfare_ppp = pcexp_ppp

  ** PASO 2 — Indicador de privación (welfare_ppp -> dep_poor1)
        gen dep_poor1 = welfare_ppp< 3 if welfare_ppp~=.
        label var dep_poor1 "Pobreza monetaria internacional. Línea: 3.00 USD - PPA 2021"

        * `apoverty` tambien sirve para sacar variables indicadoras de pobreza. Aca para la linea y el agregado de pobreza nacional
        apoverty GTpc_dr [aw = weight_hh], varpl(zref) gen(monetary)

        save "${gdStata}/Data Clean $MPM/DataComplete_with_Deprivations.dta", replace


* Recorte de variables: nos quedamos solo con lo necesario para calcular
* el MPM con `mpitb` (03_calculo_mpm_mpitb.do), evitando cargar toda la
* base de la encuesta en ese paso.
    preserve
        keep hhid provincia cod_provincia cod_CV_CP q1_03_edad hhsize weight_hh pcexp_ppp ///
            educat7 asistencia_escolar electricity imp_san_rec imp_wat_rec ///
            dep_educ_com  dep_educ_enr dep_infra_elec dep_infra_imps ///
            dep_infra_impw dep_poor1 quintile  cities monetary1  //welfare_ppp (se conserva comentado: no se usa en el paso de mpitb pero podría ser útil para chequeos)
        save "${gdStata}/Data Clean $MPM/DataDeprivations${MPM}.dta", replace
    restore
