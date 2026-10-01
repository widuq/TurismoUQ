SET SERVEROUTPUT ON;

DECLARE

    /* ============================================================
       TIPOS DE COLECCIONES
       ============================================================ */

    TYPE t_num IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    TYPE t_date IS TABLE OF DATE INDEX BY PLS_INTEGER;
    TYPE t_texto IS TABLE OF VARCHAR2(150) INDEX BY PLS_INTEGER;

    /* ============================================================
       COLECCIONES PARA ALOJAMIENTOS Y HABITACIONES
       ============================================================ */

    v_inicio_hab        t_num;
    v_cantidad_hab      t_num;
    v_tipo_hab          t_texto;
    v_capacidad_hab     t_num;
    v_base_hab          t_num;

    /* ============================================================
       COLECCIONES PARA RESERVAS
       ============================================================ */

    v_res_alojamiento   t_num;
    v_res_base          t_num;
    v_res_estado        t_texto;

    /* ============================================================
       COLECCIONES PARA SERVICIOS
       ============================================================ */

    v_serv_nombre       t_texto;
    v_serv_precio       t_num;

    /* ============================================================
       VARIABLES GENERALES
       ============================================================ */

    v_municipio         NUMBER;
    v_tipo_alojamiento  NUMBER;
    v_nombre_municipio  VARCHAR2(50);
    v_prefijo           VARCHAR2(50);
    v_nombre            VARCHAR2(150);
    v_direccion         VARCHAR2(150);
    v_correo            VARCHAR2(50);
    v_telefono          VARCHAR2(20);

    v_hab_id            NUMBER := 0;
    v_tipo              VARCHAR2(50);
    v_capacidad         NUMBER;
    v_precio_base       NUMBER;

    v_temporada         NUMBER;
    v_multiplicador     NUMBER;
    v_precio            NUMBER;

    v_cliente            NUMBER;
    v_anio               NUMBER;
    v_mes                NUMBER;
    v_inicio_mes         DATE;
    v_dias_mes           NUMBER;
    v_checkin            DATE;
    v_checkout           DATE;
    v_noche              NUMBER;
    v_estado             VARCHAR2(20);
    v_alojamiento        NUMBER;

    v_offset1            NUMBER;
    v_offset2            NUMBER;
    v_hab1               NUMBER;
    v_hab2               NUMBER;
    v_huespedes          NUMBER;

    v_servicio1          NUMBER;
    v_servicio2          NUMBER;

    v_monto              NUMBER;
    v_metodo              VARCHAR2(30);
    v_estado_pago        VARCHAR2(20);

    v_calificacion       NUMBER;

    /* ============================================================
       DATOS AUXILIARES
       ============================================================ */

    TYPE t_lista IS TABLE OF VARCHAR2(100) INDEX BY PLS_INTEGER;

    v_nombres t_lista;
    v_apellidos t_lista;
    v_ciudades t_lista;

    /* ============================================================
       FUNCIÓN PARA GENERAR MESES CON ESTACIONALIDAD
       
       Mayor peso:
       - Enero
       - Abril
       - Junio
       - Julio
       - Diciembre
       ============================================================ */

    FUNCTION obtener_mes RETURN PLS_INTEGER IS
        v_random NUMBER;
    BEGIN
        v_random := DBMS_RANDOM.VALUE(0,100);

        IF v_random < 12 THEN
            RETURN 1;       -- Enero
        ELSIF v_random < 17 THEN
            RETURN 2;       -- Febrero
        ELSIF v_random < 23 THEN
            RETURN 3;       -- Marzo
        ELSIF v_random < 33 THEN
            RETURN 4;       -- Abril
        ELSIF v_random < 38 THEN
            RETURN 5;       -- Mayo
        ELSIF v_random < 50 THEN
            RETURN 6;       -- Junio
        ELSIF v_random < 62 THEN
            RETURN 7;       -- Julio
        ELSIF v_random < 68 THEN
            RETURN 8;       -- Agosto
        ELSIF v_random < 72 THEN
            RETURN 9;       -- Septiembre
        ELSIF v_random < 76 THEN
            RETURN 10;      -- Octubre
        ELSIF v_random < 82 THEN
            RETURN 11;      -- Noviembre
        ELSE
            RETURN 12;      -- Diciembre
        END IF;
    END;

    /* ============================================================
       FUNCIÓN PARA GENERAR TIPO DE HABITACIÓN
       ============================================================ */

    FUNCTION obtener_tipo_habitacion(
        p_tipo_alojamiento NUMBER
    ) RETURN VARCHAR2 IS

        v_random NUMBER;

    BEGIN

        v_random := DBMS_RANDOM.VALUE(1,101);

        /* HOTEL */
        IF p_tipo_alojamiento = 1 THEN

            IF v_random <= 45 THEN
                RETURN 'SENCILLA';
            ELSIF v_random <= 80 THEN
                RETURN 'DOBLE';
            ELSE
                RETURN 'SUITE';
            END IF;

        /* FINCA CAFETERA */
        ELSIF p_tipo_alojamiento = 2 THEN

            IF v_random <= 20 THEN
                RETURN 'SENCILLA';
            ELSIF v_random <= 50 THEN
                RETURN 'DOBLE';
            ELSIF v_random <= 75 THEN
                RETURN 'SUITE';
            ELSE
                RETURN 'CABAÑA';
            END IF;

        /* GLAMPING */
        ELSIF p_tipo_alojamiento = 3 THEN

            IF v_random <= 15 THEN
                RETURN 'SENCILLA';
            ELSIF v_random <= 35 THEN
                RETURN 'DOBLE';
            ELSIF v_random <= 65 THEN
                RETURN 'SUITE';
            ELSE
                RETURN 'CABAÑA';
            END IF;

        /* HOSTAL */
        ELSE

            IF v_random <= 50 THEN
                RETURN 'SENCILLA';
            ELSIF v_random <= 90 THEN
                RETURN 'DOBLE';
            ELSE
                RETURN 'SUITE';
            END IF;

        END IF;

    END;


    /* ============================================================
       CAPACIDAD SEGÚN TIPO DE HABITACIÓN
       ============================================================ */

    FUNCTION obtener_capacidad(
        p_tipo VARCHAR2
    ) RETURN NUMBER IS

    BEGIN

        IF p_tipo = 'SENCILLA' THEN
            RETURN TRUNC(DBMS_RANDOM.VALUE(1,3));

        ELSIF p_tipo = 'DOBLE' THEN
            RETURN TRUNC(DBMS_RANDOM.VALUE(2,5));

        ELSIF p_tipo = 'SUITE' THEN
            RETURN TRUNC(DBMS_RANDOM.VALUE(2,5));

        ELSE
            RETURN TRUNC(DBMS_RANDOM.VALUE(2,7));

        END IF;

    END;


    /* ============================================================
       PRECIO BASE POR TIPO DE HABITACIÓN
       ============================================================ */

    FUNCTION obtener_precio_base(
        p_tipo VARCHAR2
    ) RETURN NUMBER IS

    BEGIN

        IF p_tipo = 'SENCILLA' THEN
            RETURN 90000;

        ELSIF p_tipo = 'DOBLE' THEN
            RETURN 140000;

        ELSIF p_tipo = 'SUITE' THEN
            RETURN 220000;

        ELSE
            RETURN 180000;

        END IF;

    END;


BEGIN

    /* ============================================================
       LISTAS DE NOMBRES
       ============================================================ */

    v_nombres(1) := 'Juan';
    v_nombres(2) := 'Carlos';
    v_nombres(3) := 'Miguel';
    v_nombres(4) := 'Andres';
    v_nombres(5) := 'Daniel';
    v_nombres(6) := 'Santiago';
    v_nombres(7) := 'Sebastian';
    v_nombres(8) := 'David';
    v_nombres(9) := 'Alejandro';
    v_nombres(10) := 'Mateo';
    v_nombres(11) := 'Laura';
    v_nombres(12) := 'Maria';
    v_nombres(13) := 'Valentina';
    v_nombres(14) := 'Camila';
    v_nombres(15) := 'Sofia';
    v_nombres(16) := 'Isabella';
    v_nombres(17) := 'Natalia';
    v_nombres(18) := 'Paula';
    v_nombres(19) := 'Daniela';
    v_nombres(20) := 'Juliana';

    v_apellidos(1) := 'Garcia';
    v_apellidos(2) := 'Rodriguez';
    v_apellidos(3) := 'Martinez';
    v_apellidos(4) := 'Lopez';
    v_apellidos(5) := 'Gomez';
    v_apellidos(6) := 'Perez';
    v_apellidos(7) := 'Sanchez';
    v_apellidos(8) := 'Ramirez';
    v_apellidos(9) := 'Torres';
    v_apellidos(10) := 'Diaz';
    v_apellidos(11) := 'Moreno';
    v_apellidos(12) := 'Vargas';
    v_apellidos(13) := 'Castro';
    v_apellidos(14) := 'Rojas';
    v_apellidos(15) := 'Mendoza';
    v_apellidos(16) := 'Restrepo';
    v_apellidos(17) := 'Cardona';
    v_apellidos(18) := 'Hernandez';
    v_apellidos(19) := 'Jimenez';
    v_apellidos(20) := 'Quintero';

    /* ============================================================
       CIUDADES DE ORIGEN DE LOS CLIENTES
       ============================================================ */

    v_ciudades(1) := 'Armenia';
    v_ciudades(2) := 'Pereira';
    v_ciudades(3) := 'Manizales';
    v_ciudades(4) := 'Bogota';
    v_ciudades(5) := 'Medellin';
    v_ciudades(6) := 'Cali';
    v_ciudades(7) := 'Cartagena';
    v_ciudades(8) := 'Barranquilla';
    v_ciudades(9) := 'Bucaramanga';
    v_ciudades(10) := 'Ibague';
    v_ciudades(11) := 'Neiva';
    v_ciudades(12) := 'Popayan';
    v_ciudades(13) := 'Santa Marta';
    v_ciudades(14) := 'Villavicencio';
    v_ciudades(15) := 'Tunja';
    v_ciudades(16) := 'Pasto';
    v_ciudades(17) := 'Monteria';
    v_ciudades(18) := 'Sincelejo';
    v_ciudades(19) := 'Valledupar';
    v_ciudades(20) := 'Cucuta';


    /* ============================================================
       1. MUNICIPIOS
       ============================================================ */

    INSERT INTO Municipio VALUES
    (1, 'Armenia', '630001');

    INSERT INTO Municipio VALUES
    (2, 'Salento', '631020');

    INSERT INTO Municipio VALUES
    (3, 'Filandia', '634001');

    INSERT INTO Municipio VALUES
    (4, 'Montenegro', '633001');

    INSERT INTO Municipio VALUES
    (5, 'Quimbaya', '634020');

    INSERT INTO Municipio VALUES
    (6, 'Calarca', '632001');

    INSERT INTO Municipio VALUES
    (7, 'La Tebaida', '633020');

    INSERT INTO Municipio VALUES
    (8, 'Circasia', '631001');

    INSERT INTO Municipio VALUES
    (9, 'Buenavista', '632060');

    INSERT INTO Municipio VALUES
    (10, 'Cordoba', '632080');

    INSERT INTO Municipio VALUES
    (11, 'Genova', '632090');

    INSERT INTO Municipio VALUES
    (12, 'Pijao', '632040');


    /* ============================================================
       2. TIPOS DE ALOJAMIENTO
       ============================================================ */

    INSERT INTO TipoAlojamiento VALUES
    (1, 'Hotel',
     'Establecimiento de alojamiento con habitaciones y servicios complementarios.');

    INSERT INTO TipoAlojamiento VALUES
    (2, 'Finca cafetera',
     'Alojamiento rural relacionado con la cultura y actividad cafetera.');

    INSERT INTO TipoAlojamiento VALUES
    (3, 'Glamping',
     'Alojamiento turístico que combina naturaleza y comodidades.');

    INSERT INTO TipoAlojamiento VALUES
    (4, 'Hostal',
     'Alojamiento turístico de menor escala con servicios compartidos o privados.');


    /* ============================================================
       3. ALOJAMIENTOS
       
       Distribución:
       
       Armenia       12
       Salento       10
       Filandia       8
       Montenegro     7
       Quimbaya       6
       Calarca        5
       La Tebaida     4
       Circasia       3
       Buenavista     2
       Cordoba        1
       Genova         1
       Pijao          1
       
       TOTAL = 60
       ============================================================ */

    FOR i IN 1..60 LOOP

        /* MUNICIPIO */

        IF i <= 12 THEN
            v_municipio := 1;
        ELSIF i <= 22 THEN
            v_municipio := 2;
        ELSIF i <= 30 THEN
            v_municipio := 3;
        ELSIF i <= 37 THEN
            v_municipio := 4;
        ELSIF i <= 43 THEN
            v_municipio := 5;
        ELSIF i <= 48 THEN
            v_municipio := 6;
        ELSIF i <= 52 THEN
            v_municipio := 7;
        ELSIF i <= 55 THEN
            v_municipio := 8;
        ELSIF i <= 57 THEN
            v_municipio := 9;
        ELSIF i = 58 THEN
            v_municipio := 10;
        ELSIF i = 59 THEN
            v_municipio := 11;
        ELSE
            v_municipio := 12;
        END IF;

        v_nombre_municipio :=
            CASE v_municipio
                WHEN 1 THEN 'Armenia'
                WHEN 2 THEN 'Salento'
                WHEN 3 THEN 'Filandia'
                WHEN 4 THEN 'Montenegro'
                WHEN 5 THEN 'Quimbaya'
                WHEN 6 THEN 'Calarca'
                WHEN 7 THEN 'La Tebaida'
                WHEN 8 THEN 'Circasia'
                WHEN 9 THEN 'Buenavista'
                WHEN 10 THEN 'Cordoba'
                WHEN 11 THEN 'Genova'
                ELSE 'Pijao'
            END;


        /* TIPO DE ALOJAMIENTO */

        IF i <= 15 THEN
            v_tipo_alojamiento := 1;
            v_prefijo := 'Hotel';

        ELSIF i <= 35 THEN
            v_tipo_alojamiento := 2;
            v_prefijo := 'Finca Cafetera';

        ELSIF i <= 45 THEN
            v_tipo_alojamiento := 3;
            v_prefijo := 'Glamping';

        ELSE
            v_tipo_alojamiento := 4;
            v_prefijo := 'Hostal';

        END IF;


        v_nombre :=
            v_prefijo || ' ' ||
            v_nombre_municipio || ' ' ||
            LPAD(i, 2, '0');

        v_direccion :=
            'Carrera ' ||
            TRUNC(DBMS_RANDOM.VALUE(1,31)) ||
            ' # ' ||
            TRUNC(DBMS_RANDOM.VALUE(1,81)) ||
            '-' ||
            TRUNC(DBMS_RANDOM.VALUE(1,100));

        v_correo :=
            'alojamiento' || i || '@turismouq.co';

        v_telefono :=
            '3' ||
            LPAD(
                TRUNC(DBMS_RANDOM.VALUE(0,1000000000)),
                9,
                '0'
            );


        INSERT INTO Alojamiento
        VALUES (
            i,
            v_municipio,
            v_tipo_alojamiento,
            v_nombre,
            v_direccion,
            TRUNC(DBMS_RANDOM.VALUE(2,6)),
            v_correo,
            v_telefono
        );

    END LOOP;


    /* ============================================================
       4. HABITACIONES
       
       Distribución asimétrica:
       
       3 alojamientos grandes: 40, 35 y 30
       12 alojamientos: entre 7 y 12
       20 alojamientos: 5
       19 alojamientos: 3
       6 alojamientos: 4
       
       TOTAL = 400
       ============================================================ */

    v_hab_id := 0;

    FOR i IN 1..60 LOOP

        IF i = 1 THEN
            v_cantidad_hab(i) := 40;

        ELSIF i = 2 THEN
            v_cantidad_hab(i) := 35;

        ELSIF i = 3 THEN
            v_cantidad_hab(i) := 30;

        ELSIF i <= 15 THEN
            v_cantidad_hab(i) :=
                12 - TRUNC((i - 4) / 2);

        ELSIF i <= 35 THEN
            v_cantidad_hab(i) := 5;

        ELSIF i <= 54 THEN
            v_cantidad_hab(i) := 3;

        ELSE
            v_cantidad_hab(i) := 4;

        END IF;


        v_inicio_hab(i) := v_hab_id + 1;


        /* Tipo de alojamiento */

        IF i <= 15 THEN
            v_tipo_alojamiento := 1;

        ELSIF i <= 35 THEN
            v_tipo_alojamiento := 2;

        ELSIF i <= 45 THEN
            v_tipo_alojamiento := 3;

        ELSE
            v_tipo_alojamiento := 4;

        END IF;


        FOR j IN 1..v_cantidad_hab(i) LOOP

            v_hab_id := v_hab_id + 1;

            v_tipo :=
                obtener_tipo_habitacion(v_tipo_alojamiento);

            v_capacidad :=
                obtener_capacidad(v_tipo);

            v_precio_base :=
                obtener_precio_base(v_tipo);

            v_tipo_hab(v_hab_id) := v_tipo;
            v_capacidad_hab(v_hab_id) := v_capacidad;
            v_base_hab(v_hab_id) := v_precio_base;


            INSERT INTO Habitacion
            VALUES (
                v_hab_id,
                i,
                j,
                v_capacidad,
                v_tipo,
                'Habitacion ' || j ||
                ' del alojamiento ' || i
            );

        END LOOP;

    END LOOP;


    /* ============================================================
       5. TEMPORADAS
       
       Se crean 3 niveles por año:
       
       Alta  -> enero y febrero
       Media -> marzo a agosto
       Baja  -> septiembre a diciembre
       
       2025 y 2026
       
       TOTAL = 6
       ============================================================ */

    INSERT INTO Temporada
    VALUES (
        1,
        'Temporada Alta 2025',
        'ALTA',
        DATE '2025-01-01',
        DATE '2025-02-28',
        2025
    );

    INSERT INTO Temporada
    VALUES (
        2,
        'Temporada Media 2025',
        'MEDIA',
        DATE '2025-03-01',
        DATE '2025-08-31',
        2025
    );

    INSERT INTO Temporada
    VALUES (
        3,
        'Temporada Baja 2025',
        'BAJA',
        DATE '2025-09-01',
        DATE '2025-12-31',
        2025
    );

    INSERT INTO Temporada
    VALUES (
        4,
        'Temporada Alta 2026',
        'ALTA',
        DATE '2026-01-01',
        DATE '2026-02-28',
        2026
    );

    INSERT INTO Temporada
    VALUES (
        5,
        'Temporada Media 2026',
        'MEDIA',
        DATE '2026-03-01',
        DATE '2026-08-31',
        2026
    );

    INSERT INTO Temporada
    VALUES (
        6,
        'Temporada Baja 2026',
        'BAJA',
        DATE '2026-09-01',
        DATE '2026-12-31',
        2026
    );


    /* ============================================================
       6. TARIFAS
       
       400 habitaciones × 6 temporadas
       = 2.400 tarifas
       
       El precio depende del tipo de habitación y del nivel
       de temporada.
       ============================================================ */

    FOR h IN 1..400 LOOP

        FOR s IN 1..6 LOOP

            IF s IN (1,4) THEN
                v_multiplicador := 1.25;

            ELSIF s IN (2,5) THEN
                v_multiplicador := 1.00;

            ELSE
                v_multiplicador := 0.80;

            END IF;


            v_precio :=
                ROUND(
                    v_base_hab(h) *
                    v_multiplicador *
                    (0.90 + DBMS_RANDOM.VALUE(0,0.20)),
                    -3
                );


            INSERT INTO Tarifa
            VALUES (
                ((h - 1) * 6) + s,
                h,
                s,
                v_precio
            );

        END LOOP;

    END LOOP;


    /* ============================================================
       7. CLIENTES
       
       3.000 clientes.
       Ciudades de origen variadas.
       ============================================================ */

    FOR i IN 1..3000 LOOP

        v_nombre :=
            v_nombres(TRUNC(DBMS_RANDOM.VALUE(1,21)));


        v_nombre :=
            v_nombre || ' ' ||
            v_apellidos(TRUNC(DBMS_RANDOM.VALUE(1,21))) ||
            ' ' ||
            v_apellidos(TRUNC(DBMS_RANDOM.VALUE(1,21)));


        INSERT INTO Cliente
        VALUES (
            i,
            v_nombre,

            CASE
                WHEN MOD(i,10) < 7 THEN 'CC'
                WHEN MOD(i,10) < 9 THEN 'CE'
                ELSE 'PASAPORTE'
            END,

            TO_CHAR(1000000000 + i),

            'cliente' || i || '@turismouq.co',

            '3' ||
            LPAD(
                TRUNC(DBMS_RANDOM.VALUE(0,1000000000)),
                9,
                '0'
            ),

            v_ciudades(
                TRUNC(DBMS_RANDOM.VALUE(1,21))
            ),

            TRUNC(
                DATE '2023-01-01' +
                TRUNC(DBMS_RANDOM.VALUE(0,1000))
            )
        );

    END LOOP;


    /* ============================================================
       8. RESERVAS
       
       25.000 reservas.
       
       2024 -> 5.000
       2025 -> 10.000
       2026 -> 10.000
       
       Estados:
       COMPLETADA -> 70 %
       CONFIRMADA -> 15 %
       CANCELADA  -> 10 %
       PENDIENTE  -> 5 %
       
       Los primeros 20.000 se concentran en alojamientos con
       servicios para poder generar 40.000 líneas de servicios.
       ============================================================ */

    FOR i IN 1..25000 LOOP

        /* Año */

        IF i <= 5000 THEN
            v_anio := 2024;

        ELSIF i <= 15000 THEN
            v_anio := 2025;

        ELSE
            v_anio := 2026;

        END IF;


        /* Mes con estacionalidad */

        v_mes := obtener_mes;


        v_inicio_mes :=
            ADD_MONTHS(
                DATE '2024-01-01',
                ((v_anio - 2024) * 12) +
                (v_mes - 1)
            );


        v_dias_mes :=
            LAST_DAY(v_inicio_mes) -
            v_inicio_mes + 1;


        v_checkin :=
            TRUNC(
                v_inicio_mes +
                TRUNC(
                    DBMS_RANDOM.VALUE(
                        0,
                        v_dias_mes
                    )
                )
            );


        /* Estadía entre 2 y 7 noches */

        v_noche :=
            2 +
            TRUNC(DBMS_RANDOM.VALUE(0,6));


        v_checkout :=
            v_checkin + v_noche;


        /* Fecha de reserva antes del check-in */

        v_cliente :=
            TRUNC(DBMS_RANDOM.VALUE(1,3001));


        /* Alojamientos con mayor demanda */

        IF i <= 20000 THEN

            v_alojamiento :=
                TRUNC(
                    DBMS_RANDOM.VALUE(1,16)
                );

        ELSE

            v_alojamiento :=
                TRUNC(
                    DBMS_RANDOM.VALUE(16,61)
                );

        END IF;


        /* Estado */

        IF MOD(i,20) <= 13 THEN
            v_estado := 'COMPLETADA';

        ELSIF MOD(i,20) <= 16 THEN
            v_estado := 'CONFIRMADA';

        ELSIF MOD(i,20) <= 18 THEN
            v_estado := 'CANCELADA';

        ELSE
            v_estado := 'PENDIENTE';

        END IF;


        v_res_alojamiento(i) := v_alojamiento;
        v_res_estado(i) := v_estado;


        /* Primera habitación */

        v_offset1 :=
            TRUNC(
                DBMS_RANDOM.VALUE(
                    0,
                    v_cantidad_hab(v_alojamiento)
                )
            );


        v_hab1 :=
            v_inicio_hab(v_alojamiento) +
            v_offset1;


        v_huespedes :=
            TRUNC(
                DBMS_RANDOM.VALUE(
                    1,
                    v_capacidad_hab(v_hab1) + 1
                )
            );


        INSERT INTO Reserva
        VALUES (
            i,
            v_cliente,
            v_checkin -
            1 -
            TRUNC(DBMS_RANDOM.VALUE(0,60)),
            v_checkin,
            v_checkout,
            v_estado
        );


        INSERT INTO ReservaHabitacion
        VALUES (
            ((i - 1) * 2) + 1,
            i,
            v_hab1,
            v_checkin,
            v_checkout,
            v_huespedes
        );


        v_res_base(i) :=
            v_base_hab(v_hab1) * v_noche;


        /* ========================================================
           Algunas reservas incluyen una segunda habitación.
           
           Primeras 5.000 reservas -> 2 habitaciones.
           Restantes -> 1 habitación.
           ======================================================== */

        IF i <= 5000 THEN

            v_offset2 :=
                MOD(
                    v_offset1 +
                    1 +
                    TRUNC(
                        DBMS_RANDOM.VALUE(
                            0,
                            v_cantidad_hab(v_alojamiento) - 1
                        )
                    ),
                    v_cantidad_hab(v_alojamiento)
                );


            v_hab2 :=
                v_inicio_hab(v_alojamiento) +
                v_offset2;


            v_huespedes :=
                TRUNC(
                    DBMS_RANDOM.VALUE(
                        1,
                        v_capacidad_hab(v_hab2) + 1
                    )
                );


            INSERT INTO ReservaHabitacion
            VALUES (
                ((i - 1) * 2) + 2,
                i,
                v_hab2,
                v_checkin + 1,
                v_checkout,
                v_huespedes
            );


            v_res_base(i) :=
                v_res_base(i) +
                (
                    v_base_hab(v_hab2) *
                    (v_noche - 1)
                );

        END IF;

    END LOOP;


    /* ============================================================
       9. PAGOS
       
       1 pago por cada reserva = 25.000
       
       Cada cuarta reserva tiene un segundo pago.
       
       25.000 + 6.250 = 31.250 pagos.
       ============================================================ */

    FOR i IN 1..25000 LOOP

        v_monto :=
            ROUND(
                v_res_base(i) *
                (0.65 + DBMS_RANDOM.VALUE(0,0.30)),
                -2
            );


        v_metodo :=
            CASE MOD(i,5)
                WHEN 0 THEN 'TARJETA_CREDITO'
                WHEN 1 THEN 'TARJETA_DEBITO'
                WHEN 2 THEN 'PSE'
                WHEN 3 THEN 'TRANSFERENCIA'
                ELSE 'EFECTIVO'
            END;


        /* Estado del primer pago */

        IF v_res_estado(i) = 'PENDIENTE' THEN

            v_estado_pago := 'PENDIENTE';

        ELSIF v_res_estado(i) = 'CANCELADA' THEN

            v_estado_pago := 'EXITOSO';

        ELSIF v_res_estado(i) = 'CONFIRMADA' THEN

            IF MOD(i,10) = 0 THEN
                v_estado_pago := 'PENDIENTE';
            ELSE
                v_estado_pago := 'EXITOSO';
            END IF;

        ELSE

            v_estado_pago := 'EXITOSO';

        END IF;


        INSERT INTO Pago
        VALUES (
            i,
            i,
            SYSDATE,
            v_monto,
            v_metodo,
            v_estado_pago
        );


        /* ========================================================
           SEGUNDO PAGO: anticipo + saldo
           ======================================================== */

        IF MOD(i,4) = 0 THEN

            IF v_res_estado(i) = 'CANCELADA' THEN

                /* Reembolso */

                INSERT INTO Pago
                VALUES (
                    25000 + TRUNC(i / 4),
                    i,
                    SYSDATE,
                    v_monto,
                    'TRANSFERENCIA',
                    'REEMBOLSADO'
                );

            ELSE

                INSERT INTO Pago
                VALUES (
                    25000 + TRUNC(i / 4),
                    i,
                    SYSDATE,
                    ROUND(
                        v_res_base(i) *
                        (0.20 + DBMS_RANDOM.VALUE(0,0.25)),
                        -2
                    ),
                    v_metodo,
                    'EXITOSO'
                );

            END IF;

        END IF;

    END LOOP;


    /* ============================================================
       10. SERVICIOS
       
       30 servicios.
       
       15 alojamientos con 2 servicios cada uno.
       ============================================================ */

    v_serv_nombre(1) := 'Desayuno';
    v_serv_precio(1) := 25000;

    v_serv_nombre(2) := 'Parqueadero';
    v_serv_precio(2) := 15000;

    v_serv_nombre(3) := 'Tour cafetero';
    v_serv_precio(3) := 60000;

    v_serv_nombre(4) := 'Piscina';
    v_serv_precio(4) := 30000;

    v_serv_nombre(5) := 'Senderismo';
    v_serv_precio(5) := 40000;

    v_serv_nombre(6) := 'Transporte aeropuerto';
    v_serv_precio(6) := 80000;

    v_serv_nombre(7) := 'Jacuzzi';
    v_serv_precio(7) := 50000;

    v_serv_nombre(8) := 'Fogata';
    v_serv_precio(8) := 20000;

    v_serv_nombre(9) := 'Masaje';
    v_serv_precio(9) := 90000;

    v_serv_nombre(10) := 'Bicicletas';
    v_serv_precio(10) := 35000;

    v_serv_nombre(11) := 'Cena';
    v_serv_precio(11) := 45000;

    v_serv_nombre(12) := 'Cata de cafe';
    v_serv_precio(12) := 35000;

    v_serv_nombre(13) := 'Guianza';
    v_serv_precio(13) := 50000;

    v_serv_nombre(14) := 'Minibar';
    v_serv_precio(14) := 30000;

    v_serv_nombre(15) := 'Pet friendly';
    v_serv_precio(15) := 20000;

    v_serv_nombre(16) := 'Spa';
    v_serv_precio(16) := 70000;

    v_serv_nombre(17) := 'Decoracion romantica';
    v_serv_precio(17) := 60000;

    v_serv_nombre(18) := 'Alquiler ATV';
    v_serv_precio(18) := 120000;

    v_serv_nombre(19) := 'Cabalgata';
    v_serv_precio(19) := 70000;

    v_serv_nombre(20) := 'Bar';
    v_serv_precio(20) := 25000;

    v_serv_nombre(21) := 'Yoga';
    v_serv_precio(21) := 30000;

    v_serv_nombre(22) := 'Lavanderia';
    v_serv_precio(22) := 20000;

    v_serv_nombre(23) := 'BBQ';
    v_serv_precio(23) := 40000;

    v_serv_nombre(24) := 'Cocina compartida';
    v_serv_precio(24) := 15000;

    v_serv_nombre(25) := 'Mirador';
    v_serv_precio(25) := 20000;

    v_serv_nombre(26) := 'Canopy';
    v_serv_precio(26) := 65000;

    v_serv_nombre(27) := 'Juegos de mesa';
    v_serv_precio(27) := 10000;

    v_serv_nombre(28) := 'Transfer local';
    v_serv_precio(28) := 30000;

    v_serv_nombre(29) := 'Fotografia';
    v_serv_precio(29) := 80000;

    v_serv_nombre(30) := 'Area de coworking';
    v_serv_precio(30) := 25000;


    FOR i IN 1..30 LOOP

        v_alojamiento :=
            TRUNC((i - 1) / 2) + 1;


        INSERT INTO Servicio
        VALUES (
            i,
            v_alojamiento,
            v_serv_nombre(i),
            'Servicio complementario ofrecido por el alojamiento.',
            v_serv_precio(i)
        );

    END LOOP;


    /* ============================================================
       11. RESERVA_SERVICIO
       
       Las primeras 20.000 reservas pertenecen a alojamientos
       con servicios.
       
       Cada una contrata los 2 servicios disponibles.
       
       20.000 × 2 = 40.000 líneas.
       ============================================================ */

    FOR i IN 1..20000 LOOP

        v_servicio1 :=
            ((v_res_alojamiento(i) - 1) * 2) + 1;

        v_servicio2 :=
            v_servicio1 + 1;


        INSERT INTO ReservaServicio
        VALUES (
            ((i - 1) * 2) + 1,
            i,
            v_servicio1,
            TRUNC(DBMS_RANDOM.VALUE(1,4)),
            v_serv_precio(v_servicio1)
        );


        INSERT INTO ReservaServicio
        VALUES (
            ((i - 1) * 2) + 2,
            i,
            v_servicio2,
            TRUNC(DBMS_RANDOM.VALUE(1,4)),
            v_serv_precio(v_servicio2)
        );

    END LOOP;


    /* ============================================================
   12. RESEÑAS

   De las 25.000 reservas:

   17.500 = COMPLETADA

   Se toma la mitad de las completadas:

   8.750 reseñas

   = 50 % de las reservas completadas.
   ============================================================ */

FOR r IN (
    SELECT
        r.id_reserva,
        r.id_cliente,
        MIN(h.id_alojamiento) AS id_alojamiento,
        MAX(rh.fecha_checkout) AS fecha_checkout
    FROM Reserva r
    INNER JOIN ReservaHabitacion rh
        ON rh.id_reserva = r.id_reserva
    INNER JOIN Habitacion h
        ON h.id_habitacion = rh.id_habitacion
    WHERE r.estado = 'COMPLETADA'
      AND MOD(r.id_reserva, 2) = 0
    GROUP BY
        r.id_reserva,
        r.id_cliente
)
LOOP

    v_calificacion :=
        TRUNC(DBMS_RANDOM.VALUE(1, 6));

    INSERT INTO Resena
    VALUES (
        r.id_reserva / 2,
        r.id_cliente,
        r.id_alojamiento,
        r.fecha_checkout +
        TRUNC(DBMS_RANDOM.VALUE(1, 31)),
        v_calificacion,

        CASE v_calificacion
            WHEN 1 THEN
                'La experiencia tuvo varios aspectos por mejorar.'
            WHEN 2 THEN
                'La experiencia fue aceptable, aunque podria mejorar.'
            WHEN 3 THEN
                'Una experiencia agradable en general.'
            WHEN 4 THEN
                'Buena experiencia y servicio.'
            ELSE
                'Excelente experiencia, muy recomendado.'
        END
    );

END LOOP;


    /* ============================================================
       13. USUARIOS DEL SISTEMA
       
       2 administradores
       8 encargados
       
       Los primeros cuatro encargados representan:
       - Hotel
       - Finca cafetera
       - Glamping
       - Hostal
       ============================================================ */

    INSERT INTO UsuarioSistema
    VALUES (
        1,
        NULL,
        'Administrador Principal',
        'admin1@turismouq.co',
        'Admin123',
        'ADMINISTRADOR',
        'admin_principal',
        SYSDATE
    );


    INSERT INTO UsuarioSistema
    VALUES (
        2,
        NULL,
        'Administrador Secundario',
        'admin2@turismouq.co',
        'Admin123',
        'ADMINISTRADOR',
        'admin_secundario',
        SYSDATE
    );


    /* Encargado de HOTEL */

    INSERT INTO UsuarioSistema
    VALUES (
        3,
        1,
        'Encargado Hotel',
        'encargado.hotel@turismouq.co',
        'Hotel123',
        'ENCARGADO',
        'encargado_hotel',
        SYSDATE
    );


    /* Encargado de FINCA CAFETERA */

    INSERT INTO UsuarioSistema
    VALUES (
        4,
        16,
        'Encargado Finca',
        'encargado.finca@turismouq.co',
        'Finca123',
        'ENCARGADO',
        'encargado_finca',
        SYSDATE
    );


    /* Encargado de GLAMPING */

    INSERT INTO UsuarioSistema
    VALUES (
        5,
        36,
        'Encargado Glamping',
        'encargado.glamping@turismouq.co',
        'Glamping123',
        'ENCARGADO',
        'encargado_glamping',
        SYSDATE
    );


    /* Encargado de HOSTAL */

    INSERT INTO UsuarioSistema
    VALUES (
        6,
        46,
        'Encargado Hostal',
        'encargado.hostal@turismouq.co',
        'Hostal123',
        'ENCARGADO',
        'encargado_hostal',
        SYSDATE
    );


    INSERT INTO UsuarioSistema
    VALUES (
        7,
        5,
        'Encargado Hotel 2',
        'encargado.hotel2@turismouq.co',
        'Hotel123',
        'ENCARGADO',
        'encargado_hotel2',
        SYSDATE
    );


    INSERT INTO UsuarioSistema
    VALUES (
        8,
        20,
        'Encargado Finca 2',
        'encargado.finca2@turismouq.co',
        'Finca123',
        'ENCARGADO',
        'encargado_finca2',
        SYSDATE
    );


    INSERT INTO UsuarioSistema
    VALUES (
        9,
        40,
        'Encargado Glamping 2',
        'encargado.glamping2@turismouq.co',
        'Glamping123',
        'ENCARGADO',
        'encargado_glamping2',
        SYSDATE
    );


    INSERT INTO UsuarioSistema
    VALUES (
        10,
        50,
        'Encargado Hostal 2',
        'encargado.hostal2@turismouq.co',
        'Hostal123',
        'ENCARGADO',
        'encargado_hostal2',
        SYSDATE
    );


    /* ============================================================
       CONFIRMAR TODA LA CARGA
       ============================================================ */

    COMMIT;


    DBMS_OUTPUT.PUT_LINE(
        '============================================'
    );

    DBMS_OUTPUT.PUT_LINE(
        'CARGA DE DATOS COMPLETADA CORRECTAMENTE'
    );

    DBMS_OUTPUT.PUT_LINE(
        '============================================'
    );

    DBMS_OUTPUT.PUT_LINE(
        'Municipios: 12'
    );

    DBMS_OUTPUT.PUT_LINE(
        'Tipos de alojamiento: 4'
    );

    DBMS_OUTPUT.PUT_LINE(
        'Alojamientos: 60'
    );

    DBMS_OUTPUT.PUT_LINE(
        'Habitaciones: 400'
    );

    DBMS_OUTPUT.PUT_LINE(
        'Temporadas: 6'
    );

    DBMS_OUTPUT.PUT_LINE(
        'Tarifas: 2.400'
    );

    DBMS_OUTPUT.PUT_LINE(
        'Clientes: 3.000'
    );

    DBMS_OUTPUT.PUT_LINE(
        'Reservas: 25.000'
    );

    DBMS_OUTPUT.PUT_LINE(
        'ReservaHabitacion: 30.000'
    );

    DBMS_OUTPUT.PUT_LINE(
        'Pagos: 31.250'
    );

    DBMS_OUTPUT.PUT_LINE(
        'Servicios: 30'
    );

    DBMS_OUTPUT.PUT_LINE(
        'ReservaServicio: 40.000'
    );

    DBMS_OUTPUT.PUT_LINE(
        'Resenas: 8.750'
    );

    DBMS_OUTPUT.PUT_LINE(
        'Usuarios: 10'
    );

    DBMS_OUTPUT.PUT_LINE(
        '============================================'
    );


EXCEPTION

    WHEN OTHERS THEN

        ROLLBACK;

        DBMS_OUTPUT.PUT_LINE(
            'ERROR DURANTE LA CARGA: ' || SQLERRM
        );

        RAISE;

END;
/