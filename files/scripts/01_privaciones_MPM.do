/*==================================================================
 PROYECTO:      Índice de Pobreza Multidimensional (IPM / MPM)
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
  ** 1a) Indicador: Ningún adulto del hogar (de la edad de grado 9 en adelante) ha
  *                 completado la educación primaria
  * Comentario:
    * En Guinea Ecuatorial, comenzando desde los 7 años, implica que a los 15 años completo 9 grado
    * 1. Adulto >= $eduage años
    * 2. Nivel educativo requerido = primaria completa (educat7>=3).

  /*
      * Nivel Educativo alcanzado 7 categorias
      gen educat7=.
        *Casos que nunca han estudiado
        replace educat7 = 1 if (inlist(q3_04_escuela,"No y tiene 20 años o menos de edad","No y es mayor de 20 años") | q3_04_escuela=="") 
        *Casos según último grado cursado
        replace educat7 = 1 if inlist(q3_05_grado,0,1)
        replace educat7 = 2 if inlist(q3_05_grado,2,3,4,5,6)
        replace educat7 = 3 if inlist(q3_05_grado,7)
        replace educat7 = 4 if inlist(q3_05_grado,8,9,10,11,12,14)
        replace educat7 = 5 if inlist(q3_05_grado,13,15)
        replace educat7 = 6 if inlist(q3_05_grado,17)
        replace educat7 = 7 if inlist(q3_05_grado,16,18,19)
          
      label define educat7 1 "Ninguno" 2 "Primaria incompleta" 3 "Primaria completa" 4 "Secundaria incompleta" 5 "Secundaria completa" 6 "Post-secundaria pero no universidad" 7 "Universidad (finalizada o no)"
      label val educat7 educat7 
      label var educat7 "Mayor nivel educación alcanzado (7 categorias)"
  */

    gen temp2 = 1 if q1_03_edad>=$eduage & q1_03_edad~=. & educat7>=3 & educat7~=.
    bys hhid: egen temp3 = sum(temp2) // no hay missings en temp3: todo hogar
                                       // tiene al menos 1 persona >= $eduage.
                                       // Es decir, temp3==0 significa que
                                       // nadie completó primaria, NO que
                                       // falten adultos en el hogar.

    gen dep_educ_com = 0
    replace dep_educ_com = 1 if temp3==0

    drop temp2 temp3
    la var dep_educ_com "MPM: Privado si el hogar NO tiene adultos $eduage+ con primaria completa"

**# Matrícula escolar (Education_enrollment)
  ****************************************************
  ** 1b) Indicador: niño/a en edad escolar actualmente no matriculado
  * Comentario:

    * Definiendo el universo primero, ninios en "edad escolar" (entre $lbage y $ubage años)
    gen edad_escolar = (q1_03_edad>=$lbage & q1_03_edad<=$ubage)
    bys hhid: egen cant_edadescolar = sum(edad_escolar)

    * No matriculado: está en edad escolar pero no asiste
    gen no_matriculado = (q1_03_edad>=$lbage & q1_03_edad<=$ubage & asistencia_escolar!=1)
        replace no_matriculado=. if q1_03_edad<$lbage | q1_03_edad>$ubage //asegurandose que si no esta en edad escolar no se le considere privado ni no privado, sino missing

    * Cantidad de niños no matriculados por hogar
    bys hhid: egen cant_no_matriculados = sum(no_matriculado)

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
  * Comentario: MPM (estándar), solo importa si el hogar tiene o no acceso a electricidad
  /*
    * Improved electricidad
    gen electricity = (inlist(q2_31_energiaLuz,1,2,3,4))
  */

    gen dep_infra_elec = (electricity==0) if electricity~=.
    la var dep_infra_elec "Privado si el hogar no tiene acceso a electricidad"

**# Saneamiento (saneamiento mejorado)
  ****************************************************
  * Comentario: imp_san_rec trata de definir "acceso a saneamiento mejorado" como se define en 
  *             JMP/GMD (baño de uso exclusivo del hogar y de tecnología mejorada).
  
  /*
  imp_san_rec = 1 (Mejorado) solo si se cumplen DOS condiciones:
    A) el hogar tiene W.C./inodoro o Letrina (pregunta 2.28), Y
    B) ese baño es de uso EXCLUSIVO del hogar (pregunta 2.29)
  Cualquier otro caso = 0 (No mejorado). Para replicarlo paso a paso:

  PASO A — Tipo de baño: q2_28_aseo (pregunta 2.28)
    1 = W.C. / inodoro   -> ver PASO A.1 (depende de cómo descarga)
    2 = Letrina          -> Mejorado (2.28D/2.28E no se usan para decidir)
    3 = Hoyo áspero / agujero abierto   -> No mejorado
    4 = Baño público                    -> No mejorado
    5 = Sin baño (en la naturaleza)     -> No mejorado
    6 = Otro                            -> No mejorado

  PASO A.1 — Si q2_28_aseo==1 (W.C.), cómo descarga (2.28B / 2.28C):
    q2_28B_fuente==1 (conectado a agua)                              -> Mejorado
    q2_28B_fuente==2 & q2_28C_conectado==1 (alcantarillado)          -> Mejorado
    q2_28B_fuente==2 & q2_28C_conectado==2 (tubería a río/mar)       -> Mejorado
    q2_28B_fuente==2 & q2_28C_conectado==3 (pozo ciego)              -> Mejorado
    2.28B/2.28C sin responder o fuera de estos códigos               -> Missing

  PASO B — Uso del baño: q2_29_aseoExclusivo (pregunta 2.29)
    1 = Exclusivo del hogar              -> mantiene el resultado del PASO A
    2 = Compartido con otro hogar        -> fuerza a No mejorado
    3 = Compartido con varios hogares    -> fuerza a No mejorado
    4 = Otro                             -> fuerza a No mejorado

  Resumen para reconstruir imp_san_rec en una sola tabla:
    Resultado PASO A   | Resultado PASO B (2.29) | imp_san_rec
    -----------------------------------------------------------
    Mejorado (W.C./Letrina) | 1 Exclusivo        | 1 Mejorado
    Mejorado (W.C./Letrina) | 2,3,4 Compartido    | 0 No mejorado
    No mejorado (resto)     | 1,2,3,4 (cualquiera)| 0 No mejorado
  */

  gen dep_infra_imps = (imp_san_rec==0) if imp_san_rec~=.
  la var dep_infra_imps "MPM: Privado si el hogar no tiene acceso a saneamiento mejorado"

**# Agua mejorada
  ****************************************************
  * Comentario: imp_wat_rec Variable  que resume "acceso a fuente de agua mejorada" (tubería, pozo protegido, agua embotellada,etc., excluyendo fuentes no protegidas)
  /*
    imp_wat_rec = 1 (Mejorado) solo si la fuente principal de agua (pregunta
    2.25) es de un tipo considerado mejorado, Y no queda "degradada" por las
    dos excepciones de pozo (rural / tratamiento). Para replicarlo paso a paso:

    PASO A — Fuente principal de agua: q2_25_aguaTomar (pregunta 2.25)
      1  = Grifo dentro de la vivienda        -> Mejorado
      2  = Grifo fuera de la vivienda         -> Mejorado
      3  = Grifo público                      -> Mejorado
      4  = Pozo público                       -> Mejorado, PERO ver PASO A.1 (puede bajar a No mejorado)
      5  = Pozo privado                       -> Mejorado, PERO ver PASO A.1 (puede bajar a No mejorado)
      6  = Río o lago                         -> No mejorado (agua superficial)
      7  = Manantial                          -> No mejorado (se asume manantial NO protegido:
                                                  el cuestionario no distingue protegido/no protegido)
      8  = Camión cisterna o tonel            -> No mejorado
      9  = Agua embotellada                   -> No mejorado (bottled water no cuenta como mejorado aquí)
      10 = Otra vivienda/empresa/institución  -> No mejorado
      11 = Otro                               -> No mejorado

    PASO A.1 — Excepciones para pozo público (4) y pozo privado (5):
      a) rural==1 (hogar rural) & q2_25_aguaTomar==4 (pozo público)
          -> baja a No mejorado, sin importar el tratamiento del agua
      b) q2_25_aguaTomar en {4 pozo público, 5 pozo privado}
        & q2_27_tratamientoAgua != "Ninguno" (el hogar SÍ trata el agua:
          la hierve, filtra, le pone cloro, etc.)
          -> baja a No mejorado (aplica en rural y en urbano)
      Si ninguna de las dos excepciones aplica, el pozo se queda Mejorado.

    Resumen para pozo (los únicos casos con lógica condicional):
      Tipo de pozo    | Zona    | ¿Trata el agua? | imp_wat_rec
      --------------------------------------------------------------
      Pozo público (4)| Urbano  | No (Ninguno)     | 1 Mejorado
      Pozo público (4)| Urbano  | Sí               | 0 No mejorado
      Pozo público (4)| Rural   | No o Sí          | 0 No mejorado
      Pozo privado (5)| Urbano/Rural | No (Ninguno)| 1 Mejorado
      Pozo privado (5)| Urbano/Rural | Sí          | 0 No mejorado

    Nota: "rural" y "q2_27_tratamientoAgua" ya vienen definidas de la limpieza
    de la base (no se construyen en este script).
  */

  gen dep_infra_impw = (imp_wat_rec==0) if imp_wat_rec~=.
  la var dep_infra_impw "MPM: Privado si el hogar no tiene acceso a agua potable mejorada"

****************************************************
** Dimensión 3: Monetaria
****************************************************
  * Comentario:
  /*
    gen ipc = 1.070633
    gen ppp = 287.6907
    gen welfare_ppp = pcexp/ipc/ppp/365
  */
        gen double welfare_ppp= pcexp_ppp
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
