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
  ** 1a) Indicador: Ningún adulto del hogar (de la edad de grado 9 en adelante) ha
  *                 completado la educación primaria
  * Comentario:
    * En Guinea Ecuatorial, comenzando desde los 7 años la primaria, implica que a los 15 años completo 9 grado
    * 1. Adulto >= $eduage años
    * 2. Nivel educativo requerido = primaria completa, Grade 9 = ESBA 3 (educat7>=3).

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

    * Adulto con nivel básico de educación (primaria completa o más)
    gen temp2 = 1 if q1_03_edad>=$eduage & q1_03_edad~=. & educat7>=3 & educat7~=.

    * Cantidad de adultos con nivel apropiado por hogar
    bys hhid: egen temp3 = sum(temp2) // no hay missings en temp3: todo hogar
                                       // tiene al menos 1 persona >= $eduage.
                                       // Es decir, temp3==0 significa que
                                       // nadie completó primaria, NO que
                                       // falten adultos en el hogar.

    * El hogar está privado si NINGÚN adulto alcanza el nivel
    gen dep_educ_com = 0
    replace dep_educ_com = 1 if temp3==0

    drop temp2 temp3
    la var dep_educ_com "MPM: Privado si el hogar NO tiene adultos $eduage+ con primaria completa"

**# Matrícula escolar (Education_enrollment)
  ****************************************************
  ** 1b) Indicador: niño/a en edad escolar actualmente no matriculado
  * Comentario:

    * Asistencia escolar
    // gen asistencia_escolar = (q3_08_asistio=="Sí")
    // label var asistencia_escolar "Asistió a institución educativa 2021/2022"

    * Definiendo los niños en "edad escolar" (entre $lbage y $ubage años)
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
    pregunta 2.31 "¿Cuál es la principal fuente de energía que se utiliza en este hogar
    para el alumbrado?"

    q2_31_energiaLuz = 1 Electricidad de la red pública -> electricity=1
                      = 2 Placa solar                   -> electricity=1
                      = 3 Generador (GASOLINA)          -> electricity=1
                      = 4 Generador (GASOIL)            -> electricity=1
                      = 5 Petróleo/keroseno             -> electricity=0
                      = 6 Gas (lámpara)                 -> electricity=0
                      = 7 Batería/Pila                  -> electricity=0
                      = 8 Vela                          -> electricity=0
                      = 9 Leña                          -> electricity=0
                      = 10 Otro                         -> electricity=0

    gen electricity = (inlist(q2_31_energiaLuz,1,2,3,4))
  */

    gen dep_infra_elec = (electricity==0) if electricity~=.
    la var dep_infra_elec "Privado si el hogar no tiene acceso a electricidad"

**# Saneamiento (saneamiento mejorado)
  ****************************************************
  * Comentario: imp_san_rec trata de definir "acceso a saneamiento mejorado" como se define en 
  *             JMP/GMD (baño de uso exclusivo del hogar y de tecnología mejorada).
  
  /*
    (2.28) ¿Qué tipo de aseo/baño utiliza principalmente este hogar? (q2_28_aseo)
        1 = W.C. / inodoro                  // Candidato a Mejorado -> depende de 2.28B/2.28C
        2 = Letrina                         // SIEMPRE Mejorado, no depende de 2.28D/2.28E
        3 = Hoyo áspero / agujero abierto   // No mejorado
        4 = Baño público                    // No mejorado
        5 = Sin baño (en la naturaleza)     // No mejorado
        6 = Otro                            // No mejorado

    (2.28A) ¿El WC/inodoro está dentro o fuera de la vivienda? (q2_28A_intext)
        1 = Interior  |  2 = Exterior       // Solo descriptiva, NO decide Mejorado/No mejorado
        (se pregunta solo a quienes respondieron 1=W.C. en 2.28)

    (2.28B) El WC/inodoro ¿está conectado a fuente de agua para descarga? (q2_28B_fuente)
        1 = Sí   // Junto con q2_28_aseo==1 -> Mejorado
        2 = No   // Pasa a mirar 2.28C

    (2.28C) El WC/inodoro ¿está conectado a…? (q2_28C_conectado)   [solo si 2.28B = No]
        1 = Sistema de alcantarillado             // -> Mejorado
        2 = Conectado a tubería que va al río/mar // -> Mejorado
        3 = Conectado a pozo ciego                // -> Mejorado
        (sin responder / fuera de estos códigos -> queda Missing)

    ** Existen en el cuestionario pero NO se usan para clasificar la Letrina como mejorada o no (ver PASO 2 más abajo: toda Letrina entra igual).
    (2.28D) La Letrina ¿está conectada a fuente de agua para descarga? (q2_28D_fuente)
    (2.28E) La Letrina ¿está conectada a…? (q2_28E_conectado)


    (2.29) ¿El baño es de uso exclusivo del hogar o compartido? (q2_29_aseoExclusivo)
        1 = Exclusivo del hogar            // Mantiene el resultado de 2.28
        2 = Compartido con otro hogar      // Fuerza a No mejorado, sin importar 2.28
        3 = Compartido con varios hogares  // Fuerza a No mejorado
        4 = Otro                           // Fuerza a No mejorado
  */

  ** Construycción del indicador
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

  gen dep_infra_imps = (imp_san_rec==0) if imp_san_rec~=.
  la var dep_infra_imps "MPM: Privado si el hogar no tiene acceso a saneamiento mejorado"

**# Agua mejorada
  ****************************************************
  * Comentario: imp_wat_rec Variable  que resume "acceso a fuente de agua mejorada" (tubería, pozo protegido, agua embotellada,etc., excluyendo fuentes no protegidas)
  /*
    (2.25) ¿De dónde obtienen principalmente el agua para todo uso, las personas
             de este hogar? (q2_25_aguaTomar)
    1  = Grifo dentro de la vivienda        // Mejorado
    2  = Grifo fuera de la vivienda         // Mejorado
    3  = Grifo público                      // Mejorado
    4  = Pozo público                       // Mejorado, PERO ver PASO 2 y 3 (puede bajar a No mejorado)
    5  = Pozo privado                       // Mejorado, PERO ver PASO 3 (puede bajar a No mejorado)
    6  = Río o lago                         // No mejorado (agua superficial)
    7  = Manantial                          // No mejorado (el cuestionario no distingue protegido/no protegido)
    8  = Camión cisterna o tonel            // No mejorado
    9  = Agua embotellada                   // No mejorado
    10 = Otra vivienda/empresa/institución  // No mejorado
    11 = Otro                               // No mejorado

    (2.26) ¿A qué distancia... y cuánto tiempo tarda para traerlo a casa?
        Distancia (km) / Tiempo (horas)   // Solo descriptiva, NO decide Mejorado/No mejorado

    (2.27) En su casa ¿Qué tratamiento le dan principalmente al agua para beber?
          (q2_27_tratamientoAgua)
    1 = Ninguno                     // Mantiene el resultado de 2.25 (no degrada el pozo)
    2 = La hierven                  // Degrada el pozo (4 o 5) a No mejorado
    3 = La filtran                  // Degrada el pozo a No mejorado
    4 = Le ponen lejía o cloro      // Degrada el pozo a No mejorado
    5 = Beben agua embotellada      // Degrada el pozo a No mejorado
    6 = Otro                        // Degrada el pozo a No mejorado

    (rural) Zona del hogar, ya construida en la limpieza (cod_CV_CP: 1=Urbano, 2=Rural)
    rural = 1 si es zona Rural, 0 si es Urbano
    // Solo afecta al Pozo público (2.25==4): en zona rural SIEMPRE es No mejorado,
    // sin importar el tratamiento del agua.

    Resumen para pozo (los únicos casos con lógica condicional):
      Tipo de pozo    | Zona         | ¿Trata el agua?  | imp_wat_rec
      --------------------------------------------------------------
      Pozo público (4)| Urbano       | No (Ninguno)     | 1 Mejorado
      Pozo público (4)| Urbano       | Sí               | 0 No mejorado
      Pozo público (4)| Rural        | No o Sí          | 0 No mejorado
      Pozo privado (5)| Urbano/Rural | No (Ninguno)     | 1 Mejorado
      Pozo privado (5)| Urbano/Rural | Sí               | 0 No mejorado

    Nota: "rural" y "q2_27_tratamientoAgua" ya vienen definidas de la limpieza
    de la base (no se construyen en este script).

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

  ** Indicador de privación del MPM
  gen dep_infra_impw = (imp_wat_rec==0) if imp_wat_rec~=.
  la var dep_infra_impw "MPM: Privado si el hogar no tiene acceso a agua potable mejorada"

****************************************************
** Dimensión 3: Monetaria
****************************************************
  * Comentario:
  /*
    
    gen ppp = 287.6907
    gen ipc = 1.070633

    gen welfare_ppp = pcexp/ipc/ppp/365
  */

        gen welfare_ppp = pcexp_ppp
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
