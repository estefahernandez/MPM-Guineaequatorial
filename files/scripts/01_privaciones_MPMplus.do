/*==================================================================
 PROYECTO:  IPM/MPM - QNG - Guinea Ecuatorial
 SCRIPT:    02_privaciones_MPMplus.do
 --------------------------------------------------------------------
 PROPÓSITO:
   Construir las variables BINARIAS de privación (0 = no privado, 1 = privado) para
   cada uno de los 6 indicadores del MPM, agrupados en 3 dimensiones:

     Dimensión 1 (Educación):        dep_educ_com, dep_educ_enr
     Dimensión 2 (Infraestructura):  dep_infra_elec, dep_infra_imps, dep_infra_impw
     Dimensión 3 (Monetaria):        dep_poor1

   Este script construye la variante MÁS EXIGENTE ("MPMplus"):
     - Umbral educativo: ESBA/secundaria (q3_05_grado>=11), adulto = 20+ años
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

* Simple renombre del identificador de hogar para usar en el comando pitb, etc
  ren interview__key hhid

***********************************************************
** Dimensión 1: Educación
***********************************************************

**# Logro educativo (Educational_attainment)
  ***********************************************************
  ** 1a) Indicador: Ningún adulto del hogar de ESBA 4 / secundaria básica
  *                 ha completado ese nivel.
  * Comentario:
    * En Guinea Ecuatorial, comenzando desde los 7 años, implica que a los
    * 20 años se completó ESBA 4 (secundaria básica completa).
    * 1. Adulto >= $eduage (20) años
    * 2. Nivel educativo requerido = ESBA 4 / secundaria básica (q3_05_grado>=11)

  /*
  dep_educ_com = 1 (Privado) si NINGÚN adulto del hogar alcanzó al menos
  ESBA 4 (secundaria básica completa).

  PASO A — ¿Hay al menos un adulto (20+) con ESBA4+ en el hogar?
    temp2 = 1 si q1_03_edad>=20 & q3_05_grado>=11 (por persona)
    temp3 = suma de temp2 por hogar (hhid)
    Si temp3==0 -> privado, salvo que aplique la excepción del PASO A.1

  PASO A.1 — Excepción "menores de 20 ya educados":
    Si el hogar NO tiene ningún adulto de 20+ años (adults_count==0,
    q1_03_edad>=20 nunca ocurre en ese hogar) PERO SÍ tiene exactamente
    una persona de 18-19 años con ESBA4+ (menores_ESBA_count==1,
    q1_03_edad>=18 & q3_05_grado>=11) -> el hogar se considera NO privado
    (se fuerza temp3=1), aunque no tenga un "adulto" formal de 20+.

  Resultado: dep_educ_com = 1 solo si temp3==0 después de aplicar la
  excepción del PASO A.1.
  */
    * temp2 = 1 si la persona es adulta (>=$eduage) y alcanzó ESBA/secundaria
    gen temp2 = 1 if q1_03_edad>=$eduage & q1_03_edad~=. & q3_05_grado>=11 & q3_05_grado~=.
    * temp3 = conteo de esos adultos por hogar (bys...egen sum: agregación
    * a nivel de grupo, ver explicación detallada en 01_limpieza_indicadores.do)
    bys hhid: egen temp3 = sum(temp2) // no hay missings en temp3: todo hogar
                                       // tiene al menos 1 persona >= $eduage

    // Excepción: el hogar se considera NO privado si es un hogar donde
    // hay personas mayores de 18 años pero nadie mayor de 20 (por lo
    // tanto temp3 no captura adultos "formales"), y al menos una de esas
    // personas de 18+ ya tiene ESBA 4 o más.
    gen menores_ESBA = (q1_03_edad>=18 & q3_05_grado>=11 & q3_05_grado~=.)
    bys hhid: egen menores_ESBA_count = sum(menores_ESBA)
    gen check_adults = (q1_03_edad>=$eduage)
    bys hhid: egen adults_count = sum(check_adults)
    replace temp3 = 1 if menores_ESBA_count==1 & adults_count==0
        drop menores_ESBA menores_ESBA_count check_adults adults_count

    gen dep_educ_com = 0
    replace dep_educ_com = 1 if temp3==0

    drop temp2 temp3 // variables temporales de conteo, ya no se necesitan
    la var dep_educ_com "MPM+: Privado si el hogar NO tiene adultos $eduage+ con secundaria completa"

  ****************************************************
  **1b) Indicador: niño/a en edad escolar actualmente no matriculado
  /*
  dep_educ_enr = 1 (Privado) si el hogar tiene al menos un niño/a en edad
  escolar (7-14 años) que NO está matriculado, O que está matriculado
  pero con 2+ años de RETRAZO. A diferencia del MPM estándar (solo
  importa "no matriculado"; ver 01_privaciones_MPM.do), aquí se suma el
  RETRAZO escolar a partir de q3_11_gradoAsistido (grado que cursa) comparado con 
  la edad esperada para ese grado.

  PASO A — Universo: niños/as en edad escolar
    temp2a = 1 si q1_03_edad entre $lbage (7) y $ubage (14)
    educ_enr_size = conteo de esos niños/as por hogar (hhid)
    Si educ_enr_size==0, el hogar no tiene niños en edad escolar y
    dep_educ_enr queda en 0 (no aplica la privación, ver PASO C).

  PASO B — ¿Está privado cada niño/a en edad escolar?
    Privado si asistencia_escolar==0 (no matriculado; pregunta 3.09
    "¿Asiste o asistió... durante el año escolar 2021-2022?" = No)
    O privado si asistencia_escolar==1 & rezago_escolar==1 (matriculado
    pero con 2+ años de atraso respecto al grado esperado para su edad)
    temp3 = conteo de niños/as privados por hogar (hhid)

  PASO C — Resultado a nivel hogar
    dep_educ_enr = 1 si temp3>0 (al menos un niño/a privado)
    dep_educ_enr = 0 si educ_enr_size==0 (sin niños en edad escolar)
  */

    * Todo niño matriculado y con más de 2 años de retrazo
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

    * Tamaño del grupo en edad escolar, por hogar (para distinguir
    * "hogar sin niños en edad escolar" de "hogar con niños, todos ok")
    gen temp2a = 1 if q1_03_edad>=$lbage & q1_03_edad<=$ubage
    bys hhid: egen educ_enr_size = sum(temp2a)

    * Privado si no está matriculado O si está matriculado con rezago
    gen temp2 = 1 if q1_03_edad>=$lbage & q1_03_edad<=$ubage & asistencia_escolar==0 // no matriculado
    replace temp2 = 1 if q1_03_edad>=$lbage & q1_03_edad<=$ubage & asistencia_escolar==1 & rezago_escolar==1 // matriculado con rezago
    bys hhid: egen temp3 = sum(temp2)

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
    (2.31) ¿Cuál es la principal fuente de energía que se utiliza en este hogar
          para el alumbrado? (q2_31_energiaLuz)
        1  = Electricidad de la red pública   // Mejorado
        2  = Placa solar                      // Mejorado
        3  = Generador (GASOLINA)             // Mejorado
        4  = Generador (GASOIL)               // Mejorado
        5  = Petróleo/Keroseno                // No mejorado
        6  = Gas (lámpara)                    // No mejorado
        7  = Batería/Pila                     // No mejorado
        8  = Vela                             // No mejorado
        9  = Leña                             // No mejorado
        10 = Otro                             // No mejorado

    (2.32) ¿A quién le pagan por el servicio de electricidad?
        1 Empresa Pública SEGESA / 2 Al vecino / 3 Autoconsumo (generador) -> 2.33
        4 No paga -> 2.33 / 5 Al propietario de la vivienda / 6 Otro
        // Solo define el ENRUTAMIENTO de la encuesta (a quién se le pregunta 2.32A
        // vs. quién pasa directo a 2.33). NO se usa para decidir Mejorado/No mejorado.

    (2.32A) En el último mes que pagó ¿cuánto fue el pago mensual por electricidad?
        // Solo descriptiva (monto en FCFA) -- NO se usa para el indicador de privación.

    (2.33) En el último mes ¿cuántos días se quedó el hogar sin energía eléctrica
          por más de 30 min? (q2_33_SinElect, numérico)
        // Se pregunta a TODO hogar que declaró tener electricidad en 2.31 (llega
        // aquí ya sea desde el pago en 2.32A o directo desde 2.32 si es
        // autoconsumo/no paga). Se usa SOLO en la variante MPM+ para penalizar
        // los cortes de luz del último mes, aunque el hogar sí tenga acceso.
  */

** PASO 1 — Acceso a electricidad mejorado (2.31 -> electricity)
    // recode q2_31_energiaLuz (1/4=1 "Improved electricity") (nonmissing=0 "Not improved electricity"), gen(electricity)
    // label var electricity "Hogar con acceso a electricidad (mejorado). Recodificado de 2.31 (q2_31_energiaLuz)"

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
    imp_san_rec = 1 (Mejorado) solo si se cumplen DOS condiciones (misma
    definición que en el MPM estándar: imp_san_rec no cambia entre
    variantes; ver el detalle completo en 01_privaciones_MPM.do):
      A) el hogar tiene W.C./inodoro o Letrina (pregunta 2.28), Y
      B) ese baño es de uso EXCLUSIVO del hogar (pregunta 2.29)
    Cualquier otro caso = 0 (No mejorado).

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
  */
      gen dep_infra_imps = (imp_san_rec==0) if imp_san_rec~=.
      la var dep_infra_imps "MPM+: Privado si el hogar no tiene acceso a saneamiento mejorado"

**# Agua mejorada
  ****************************************************
  /*
    imp_wat_rec (MPM+) es MÁS ESTRICTO que en el MPM estándar: el POZO
    PÚBLICO queda excluido de "mejorado" en TODOS los casos (no solo en
    zona rural), y el POZO PRIVADO deja de contar como mejorado si el
    hogar trata el agua. Para replicarlo paso a paso:

    PASO A — Fuente principal de agua: q2_25_aguaTomar (pregunta 2.25)
      1  = Grifo dentro de la vivienda        -> Mejorado
      2  = Grifo fuera de la vivienda         -> Mejorado
      3  = Grifo público                      -> Mejorado
      4  = Pozo público                       -> SIEMPRE No mejorado en MPM+
                                                  (en el MPM estándar sí cuenta
                                                  como mejorado en zona urbana)
      5  = Pozo privado                       -> Mejorado, PERO ver PASO A.1
      6  = Río o lago                         -> No mejorado (agua superficial)
      7  = Manantial                          -> No mejorado (se asume no protegido)
      8  = Camión cisterna o tonel            -> No mejorado
      9  = Agua embotellada                   -> No mejorado
      10 = Otra vivienda/empresa/institución  -> No mejorado
      11 = Otro                               -> No mejorado

    PASO A.1 — Excepción para pozo privado (5):
      q2_25_aguaTomar==5 & q2_27_tratamientoAgua != "Ninguno"
      (el hogar SÍ trata el agua: la hierve, filtra, le pone cloro, etc.)
        -> baja a No mejorado
      Si el hogar NO trata el agua (tratamiento=="Ninguno") -> se queda Mejorado

    Resumen:
      Fuente           | ¿Trata el agua? | imp_wat_rec (MPM+)
      -----------------------------------------------------------
      Pozo público (4) | No aplica        | 0 No mejorado (siempre)
      Pozo privado (5) | No (Ninguno)     | 1 Mejorado
      Pozo privado (5) | Sí               | 0 No mejorado

    Diferencia clave vs. MPM estándar (01_privaciones_MPM.do):
      - MPM estándar: pozo público es Mejorado en zona urbana (No mejorado
        solo si es rural, o si se trata el agua).
      - MPM+: pozo público es SIEMPRE No mejorado, sin importar zona ni
        tratamiento.
      - En ambas variantes, el pozo privado sigue la misma regla (Mejorado
        salvo que se trate el agua).
  */
        drop water14
        * Recategorización de la fuente de agua (14 categorías estándar):
        * en la variante MPM+ TODO pozo público se considera NO
        * mejorado, y el pozo privado se considera mejorado SOLO si
        * recibió algún tipo de tratamiento (ver `replace` justo abajo).
        recode q2_25_aguaTomar (1=1) (2=2) (3=3) (4=10) (5=5) (6=13) (7=9) (8=12) (9=7) (10=14) (11=14) (nonmissing= 0), gen(water14)

        * Excepción: pozo protegido (código 5) se reclasifica como NO
        * mejorado (código 10) salvo que declare tratamiento de agua.
        replace water14 = 10 if inlist(q2_25_aguaTomar, 5) & q2_27_tratamientoAgua!= "Ninguno"
        label var water14 "Fuente de agua: 14 categorías"
        label define water14 1 "Agua entubada dentro de la vivienda" 2 "Agua entubada al patio/parcela" 3 "Grifo o pilón público" 4 "Pozo entubado o perforado" 5 "Pozo protegido" 6 "Manantial protegido" 7 "Agua embotellada" 8 "Agua de lluvia" 9 "Manantial no protegido" 10 "Pozo no protegido" 11 "Carro con tanque/tambor pequeño" 12 "Camión cisterna" 13 "Agua superficial" 14  "Otro", replace
        label val water14 water14

        * Agua mejorada (recodificación desde water14)
        drop imp_wat_rec
        recode water14 (1/6 8=1 "Acceso a fuente de agua mejorada") (nonmissing=0 "Sin acceso a fuente de agua mejorada"), gen(imp_wat_rec)
        label var imp_wat_rec "Hogar con acceso a fuente de agua mejorada. Recodificada desde water14 siguiendo GMD. Igual a drinking_water"

        gen dep_infra_impw = (imp_wat_rec==0) if imp_wat_rec~=.
        la var dep_infra_impw "MPM+: Privado si el hogar no tiene acceso a agua potable mejorada (excluye pozo)"

****************************************************
** Dimensión 3: Monetaria
****************************************************
* Comentario: dep_poor1 = 1 (Privado) si el gasto per cápita del hogar en PPA
*             (pcexp_ppp) es menor a la línea de pobreza.

  /*
    gen ipc = 1.070633
    gen ppp = 287.6907
    gen welfare_ppp = pcexp/ipc/ppp/365
  */

    gen double welfare_ppp= pcexp_ppp
    gen dep_poor1 = welfare_ppp< 8.30 if welfare_ppp~=.
    label var dep_poor1 "Pobreza monetaria internacional. Línea: 8.30 USD - PPA 2021"

    * `apoverty` tambien sirve para sacar variables indicadoras de pobreza. Aca para la linea y el agregado de pobreza nacional
    apoverty GTpc_dr [aw = weight_hh], varpl(zref) gen(monetary)

    save "${gdStata}/Data Clean $MPM/DataComplete_with_Deprivations.dta", replace


* Recorte de variables: nos quedamos solo con lo necesario para calcular
* el IPM con `mpitb` (03_calculo_mpm_mpitb.do), evitando cargar toda la
* base de la encuesta en ese paso.
    preserve
        keep hhid provincia cod_provincia cod_CV_CP q1_03_edad hhsize weight_hh pcexp_ppp ///
            educat7 asistencia_escolar electricity imp_san_rec imp_wat_rec ///
            dep_educ_com educ_enr_size dep_educ_enr dep_infra_elec dep_infra_imps ///
            dep_infra_impw dep_poor1 quintile cities monetary1  //welfare_ppp (se conserva comentado: no se usa en el paso de mpitb pero podría ser útil para chequeos)
        save "${gdStata}/Data Clean $MPM/DataDeprivations${MPM}.dta", replace
    restore
