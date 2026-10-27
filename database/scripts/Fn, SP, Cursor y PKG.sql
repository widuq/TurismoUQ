-- PROYECTO INTEGRADOR: TURISMOUQ - PLATAFORMA DE RESERVAS
-- ASIGNATURA: BASES DE DATOS II
-- Script: Funciones,Procedimientos, Cursores y Paquete
-- Entrega 2 del Proyecto

-- Ejecutar lo siguiente conectado como un usuario con permisos SYSTEM 
GRANT CREATE PROCEDURE TO PROYECTO;
GRANT CREATE TRIGGER TO PROYECTO;
GRANT CREATE TABLESPACE TO PROYECTO;
GRANT CREATE MATERIALIZED VIEW TO PROYECTO;
GRANT CREATE VIEW TO PROYECTO;

-- Permite al usuario consultar tablas en transacciones y manejar vistas 
-- materializadas
GRANT QUERY REWRITE TO PROYECTO;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED;

-- Estructuras de soporte para auditoría y liquidación
-- Tabla para registrar la auditoría de cambios sobre la tabla TARIFA
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE AuditoriaTarifa CASCADE CONSTRAINTS PURGE';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

CREATE TABLE AuditoriaTarifa (
    id_auditoria     NUMBER(10)    NOT NULL,
    id_tarifa        NUMBER(10),
    id_habitacion    NUMBER(10),
    id_temporada     NUMBER(10),
    precio_anterior  NUMBER(12,2),
    precio_nuevo     NUMBER(12,2),
    operacion        VARCHAR2(20)  NOT NULL,
    usuario          VARCHAR2(50)  NOT NULL,
    fecha_cambio     DATE          NOT NULL,
    CONSTRAINT pk_auditoria_tarifa PRIMARY KEY (id_auditoria)
);

COMMENT ON TABLE AuditoriaTarifa IS 
'Registro histórico de auditoría de modificaciones sobre las tarifas de habitaciones.';
COMMENT ON COLUMN AuditoriaTarifa.id_auditoria IS 
'Identificador secuencial del evento de auditoría.';
COMMENT ON COLUMN AuditoriaTarifa.id_tarifa IS 
'Identificador de la tarifa afectada.';
COMMENT ON COLUMN AuditoriaTarifa.id_habitacion IS 
'Habitación a la que pertenece la tarifa.';
COMMENT ON COLUMN AuditoriaTarifa.id_temporada IS 
'Temporada de la tarifa.';
COMMENT ON COLUMN AuditoriaTarifa.precio_anterior IS 
'Precio por noche antes de la modificación.';
COMMENT ON COLUMN AuditoriaTarifa.precio_nuevo IS 
'Precio por noche posterior a la modificación.';
COMMENT ON COLUMN AuditoriaTarifa.operacion IS 
'Tipo de operación DML: INSERT, UPDATE o DELETE.';
COMMENT ON COLUMN AuditoriaTarifa.usuario IS 
'Usuario de base de datos que ejecutó la sentencia.';
COMMENT ON COLUMN AuditoriaTarifa.fecha_cambio IS 
'Fecha y hora exacta en la que se realizó la operación.';

-- Secuencia para la tabla de auditoría
BEGIN
    EXECUTE IMMEDIATE 'DROP SEQUENCE seq_auditoria_tarifa';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/
CREATE SEQUENCE seq_auditoria_tarifa START WITH 1 INCREMENT BY 1 NOCACHE;


-- Tabla para persistir los resultados del proceso masivo de liquidación mensual
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE LiquidacionMensual CASCADE CONSTRAINTS PURGE';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

CREATE TABLE LiquidacionMensual (
    id_liquidacion           NUMBER(10)   NOT NULL,
    id_alojamiento           NUMBER(10)   NOT NULL,
    anio                     NUMBER(4)    NOT NULL,
    mes                      NUMBER(2)    NOT NULL,
    total_reservas           NUMBER(8)    NOT NULL,
    total_noches             NUMBER(8)    NOT NULL,
    total_ingresos_estadia   NUMBER(14,2) NOT NULL,
    total_ingresos_servicios NUMBER(14,2) NOT NULL,
    total_bruto              NUMBER(14,2) NOT NULL,
    comision_plataforma      NUMBER(14,2) NOT NULL,
    monto_neto_alojamiento   NUMBER(14,2) NOT NULL,
    fecha_liquidacion        DATE DEFAULT SYSDATE NOT NULL,
    estado                   VARCHAR2(20) DEFAULT 'PROCESADO' NOT NULL,
    
    CONSTRAINT pk_liquidacion_mensual PRIMARY KEY (id_liquidacion),
    CONSTRAINT fk_liq_alojamiento FOREIGN KEY (id_alojamiento) REFERENCES Alojamiento(id_alojamiento),
    CONSTRAINT uq_liq_alojamiento_periodo UNIQUE (id_alojamiento, anio, mes),
    CONSTRAINT ck_liq_mes CHECK (mes BETWEEN 1 AND 12)
);

COMMENT ON TABLE LiquidacionMensual IS
'Historial de liquidaciones mensuales masivas generadas por alojamiento.';

BEGIN
    EXECUTE IMMEDIATE 'DROP SEQUENCE seq_liquidacion_mensual';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/
CREATE SEQUENCE seq_liquidacion_mensual START WITH 1 INCREMENT BY 1 NOCACHE;


-- Crear el paquete PL/SQL: PKG_TURISMOUQ
CREATE OR REPLACE PACKAGE PKG_TURISMOUQ AS

    -- Códigos de excepción estandarizados para la plataforma
    ERR_HABITACION_NO_DISPONIBLE CONSTANT NUMBER := -20001;
    ERR_CHECKOUT_INVALIDO        CONSTANT NUMBER := -20002;
    ERR_CAPACIDAD_EXCEDIDA       CONSTANT NUMBER := -20003;
    ERR_CLIENTE_NO_EXISTE        CONSTANT NUMBER := -20004;
    ERR_HABITACION_NO_EXISTE     CONSTANT NUMBER := -20005;
    ERR_TEMPORADA_NO_EXISTE      CONSTANT NUMBER := -20006;
    ERR_TARIFA_NO_EXISTE         CONSTANT NUMBER := -20007;

    -- Cursor explícito con parámetros para la liquidación mensual masiva
    CURSOR c_liquidacion_alojamientos(
        cp_anio           NUMBER,
        cp_mes            NUMBER,
        cp_id_alojamiento NUMBER DEFAULT NULL
    ) IS
        WITH PagosPorReserva AS (
            SELECT 
                id_reserva,
                SUM(monto) AS total_pagado
            FROM Pago
            WHERE estado = 'EXITOSO'
            GROUP BY id_reserva
        ),
        ServiciosPorReserva AS (
            SELECT 
                id_reserva,
                SUM(cantidad * precio_unitario) AS total_servicios
            FROM ReservaServicio
            GROUP BY id_reserva
        ),
        ReservaAlojamiento AS (
            SELECT 
                rh.id_reserva,
                h.id_alojamiento,
                SUM(rh.fecha_checkout - rh.fecha_checkin) AS noches_reserva
            FROM ReservaHabitacion rh
            JOIN Habitacion h ON rh.id_habitacion = h.id_habitacion
            GROUP BY rh.id_reserva, h.id_alojamiento
        )
        SELECT 
            a.id_alojamiento,
            a.nombre AS nombre_alojamiento,
            m.nombre AS nombre_municipio,
            COUNT(DISTINCT r.id_reserva) AS total_reservas,
            NVL(SUM(ra.noches_reserva), 0) AS total_noches,
            NVL(SUM(pr.total_pagado), 0) AS total_ingresos_estadia,
            NVL(SUM(sr.total_servicios), 0) AS total_ingresos_servicios,
            (NVL(SUM(pr.total_pagado), 0) + NVL(SUM(sr.total_servicios), 0)) AS total_bruto,
            ROUND((NVL(SUM(pr.total_pagado), 0) + NVL(SUM(sr.total_servicios), 0)) * 0.10, 2) AS comision_plataforma,
            ROUND((NVL(SUM(pr.total_pagado), 0) + NVL(SUM(sr.total_servicios), 0)) * 0.90, 2) AS monto_neto_alojamiento
        FROM Alojamiento a
        JOIN Municipio m ON a.id_municipio = m.id_municipio
        JOIN ReservaAlojamiento ra ON a.id_alojamiento = ra.id_alojamiento
        JOIN Reserva r ON ra.id_reserva = r.id_reserva
        LEFT JOIN PagosPorReserva pr ON r.id_reserva = pr.id_reserva
        LEFT JOIN ServiciosPorReserva sr ON r.id_reserva = sr.id_reserva
        WHERE r.estado = 'COMPLETADA'
          AND EXTRACT(YEAR FROM r.fecha_checkout) = cp_anio
          AND EXTRACT(MONTH FROM r.fecha_checkout) = cp_mes
          AND (cp_id_alojamiento IS NULL OR a.id_alojamiento = cp_id_alojamiento)
        GROUP BY a.id_alojamiento, a.nombre, m.nombre
        ORDER BY total_bruto DESC;

    -- Declaración de la función fn_valor_estadia
    FUNCTION fn_valor_estadia(
        p_id_habitacion IN NUMBER,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) RETURN NUMBER;

    -- Declaración del procedimiento sp_crear_reserva
    PROCEDURE sp_crear_reserva(
        p_id_cliente         IN  NUMBER,
        p_id_habitacion      IN  NUMBER,
        p_fecha_checkin      IN  DATE,
        p_fecha_checkout     IN  DATE,
        p_cantidad_huespedes IN  NUMBER,
        p_id_reserva         OUT NUMBER
    );

    -- Declaración del procedimiento de liquidación mensual
    PROCEDURE sp_liquidacion_mensual(
        p_anio            IN NUMBER,
        p_mes             IN NUMBER,
        p_id_alojamiento  IN NUMBER DEFAULT NULL
    );

END PKG_TURISMOUQ;
/

-- Cuerpo del paquete: PKG_TURISMOUQ
CREATE OR REPLACE PACKAGE BODY PKG_TURISMOUQ AS

    -- fn_valor_estadia
    FUNCTION fn_valor_estadia(
        p_id_habitacion IN NUMBER,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) RETURN NUMBER IS
        v_total_noches     NUMBER;
        v_valor_acumulado  NUMBER(12,2) := 0;
        v_fecha_noche      DATE;
        v_id_temporada     NUMBER;
        v_precio_noche     NUMBER(12,2);
        v_existe_hab       NUMBER;
    BEGIN
        IF p_fecha_in IS NULL OR p_fecha_out IS NULL THEN
            RAISE_APPLICATION_ERROR(
                ERR_CHECKOUT_INVALIDO, 
                'fn_valor_estadia: Las fechas de checkin y checkout son obligatorias.'
            );
        END IF;

        IF TRUNC(p_fecha_out) <= TRUNC(p_fecha_in) THEN
            RAISE_APPLICATION_ERROR(
                ERR_CHECKOUT_INVALIDO, 
                'fn_valor_estadia: La fecha de checkout (' || TO_CHAR(p_fecha_out, 'YYYY-MM-DD') || 
                ') debe ser posterior a la fecha de checkin (' || TO_CHAR(p_fecha_in, 'YYYY-MM-DD') || ').'
            );
        END IF;

        SELECT COUNT(*)
        INTO v_existe_hab
        FROM Habitacion
        WHERE id_habitacion = p_id_habitacion;

        IF v_existe_hab = 0 THEN
            RAISE_APPLICATION_ERROR(
                ERR_HABITACION_NO_EXISTE, 
                'fn_valor_estadia: La habitación con ID ' || p_id_habitacion || ' no existe.'
            );
        END IF;

        v_total_noches := TRUNC(p_fecha_out) - TRUNC(p_fecha_in);

        FOR i IN 0 .. (v_total_noches - 1) LOOP
            v_fecha_noche := TRUNC(p_fecha_in) + i;

            BEGIN
                SELECT t.id_temporada
                INTO v_id_temporada
                FROM Temporada t
                WHERE v_fecha_noche BETWEEN t.fecha_inicio AND t.fecha_fin;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    RAISE_APPLICATION_ERROR(
                        ERR_TEMPORADA_NO_EXISTE, 
                        'fn_valor_estadia: No existe una temporada definida para la fecha ' || 
                        TO_CHAR(v_fecha_noche, 'YYYY-MM-DD') || '.'
                    );
                WHEN TOO_MANY_ROWS THEN
                    RAISE_APPLICATION_ERROR(
                        ERR_TEMPORADA_NO_EXISTE, 
                        'fn_valor_estadia: Existen temporadas solapadas para la fecha ' || 
                        TO_CHAR(v_fecha_noche, 'YYYY-MM-DD') || '.'
                    );
            END;

            BEGIN
                SELECT tar.precio_noche
                INTO v_precio_noche
                FROM Tarifa tar
                WHERE tar.id_habitacion = p_id_habitacion
                  AND tar.id_temporada = v_id_temporada;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    RAISE_APPLICATION_ERROR(
                        ERR_TARIFA_NO_EXISTE, 
                        'fn_valor_estadia: No existe tarifa registrada para la habitación ' || 
                        p_id_habitacion || ' en la temporada ' || v_id_temporada || 
                        ' (Fecha: ' || TO_CHAR(v_fecha_noche, 'YYYY-MM-DD') || ').'
                    );
            END;

            v_valor_acumulado := v_valor_acumulado + v_precio_noche;
        END LOOP;

        RETURN v_valor_acumulado;
    END fn_valor_estadia;

    -- sp_crear_reserva
    PROCEDURE sp_crear_reserva(
        p_id_cliente         IN  NUMBER,
        p_id_habitacion      IN  NUMBER,
        p_fecha_checkin      IN  DATE,
        p_fecha_checkout     IN  DATE,
        p_cantidad_huespedes IN  NUMBER,
        p_id_reserva         OUT NUMBER
    ) IS
        v_existe_cliente    NUMBER;
        v_capacidad_maxima  NUMBER;
        v_solapados         NUMBER;
        v_nuevo_id_reserva  NUMBER;
        v_nuevo_id_reshab   NUMBER;
    BEGIN
        IF p_fecha_checkin IS NULL OR p_fecha_checkout IS NULL THEN
            RAISE_APPLICATION_ERROR(
                ERR_CHECKOUT_INVALIDO, 
                'Error [-20002]: Las fechas de checkin y checkout son obligatorias.'
            );
        END IF;

        IF TRUNC(p_fecha_checkout) <= TRUNC(p_fecha_checkin) THEN
            RAISE_APPLICATION_ERROR(
                ERR_CHECKOUT_INVALIDO, 
                'Error [-20002]: La fecha de checkout (' || TO_CHAR(p_fecha_checkout, 'YYYY-MM-DD') || 
                ') debe ser estrictamente posterior a la fecha de checkin (' || 
                TO_CHAR(p_fecha_checkin, 'YYYY-MM-DD') || ').'
            );
        END IF;

        SELECT COUNT(*)
        INTO v_existe_cliente
        FROM Cliente
        WHERE id_cliente = p_id_cliente;

        IF v_existe_cliente = 0 THEN
            RAISE_APPLICATION_ERROR(
                ERR_CLIENTE_NO_EXISTE, 
                'Error [-20004]: El cliente con identificador ' || p_id_cliente || ' no existe en el sistema.'
            );
        END IF;

        BEGIN
            SELECT capacidad_maxima
            INTO v_capacidad_maxima
            FROM Habitacion
            WHERE id_habitacion = p_id_habitacion;
        EXCEPTIOn
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(
                    ERR_HABITACION_NO_EXISTE, 
                    'Error [-20005]: La habitación con ID ' || p_id_habitacion || ' no existe.'
                );
        END;

        IF p_cantidad_huespedes IS NULL OR p_cantidad_huespedes <= 0 THEN
            RAISE_APPLICATION_ERROR(
                ERR_CAPACIDAD_EXCEDIDA, 
                'Error [-20003]: La cantidad de huéspedes debe ser mayor a 0.'
            );
        END IF;

        IF p_cantidad_huespedes > v_capacidad_maxima THEN
            RAISE_APPLICATION_ERROR(
                ERR_CAPACIDAD_EXCEDIDA, 
                'Error [-20003]: Capacidad excedida. La cantidad solicitada (' || p_cantidad_huespedes || 
                ' huéspedes) supera la capacidad máxima de la habitación ' || p_id_habitacion || 
                ' (' || v_capacidad_maxima || ' personas).'
            );
        END IF;

        SELECT COUNT(*)
        INTO v_solapados
        FROM ReservaHabitacion rh
        JOIN Reserva r ON rh.id_reserva = r.id_reserva
        WHERE rh.id_habitacion = p_id_habitacion
          AND r.estado IN ('PENDIENTE', 'CONFIRMADA', 'COMPLETADA')
          AND TRUNC(p_fecha_checkin) < TRUNC(rh.fecha_checkout)
          AND TRUNC(p_fecha_checkout) > TRUNC(rh.fecha_checkin);

        IF v_solapados > 0 THEN
            RAISE_APPLICATION_ERROR(
                ERR_HABITACION_NO_DISPONIBLE, 
                'Error [-20001]: Habitación no disponible. La habitación ' || p_id_habitacion || 
                ' ya cuenta con una reserva activa en el periodo entre ' || 
                TO_CHAR(p_fecha_checkin, 'YYYY-MM-DD') || ' y ' || 
                TO_CHAR(p_fecha_checkout, 'YYYY-MM-DD') || '.'
            );
        END IF;

        SELECT NVL(MAX(id_reserva), 0) + 1
        INTO v_nuevo_id_reserva
        FROM Reserva;

        SELECT NVL(MAX(id_reserva_habitacion), 0) + 1
        INTO v_nuevo_id_reshab
        FROM ReservaHabitacion;

        INSERT INTO Reserva (
            id_reserva,
            id_cliente,
            fecha_reserva,
            fecha_checkin,
            fecha_checkout,
            estado
        ) VALUES (
            v_nuevo_id_reserva,
            p_id_cliente,
            SYSDATE,
            TRUNC(p_fecha_checkin),
            TRUNC(p_fecha_checkout),
            'CONFIRMADA'
        );

        INSERT INTO ReservaHabitacion (
            id_reserva_habitacion,
            id_reserva,
            id_habitacion,
            fecha_checkin,
            fecha_checkout,
            cantidad_huespedes
        ) VALUES (
            v_nuevo_id_reshab,
            v_nuevo_id_reserva,
            p_id_habitacion,
            TRUNC(p_fecha_checkin),
            TRUNC(p_fecha_checkout),
            p_cantidad_huespedes
        );

        p_id_reserva := v_nuevo_id_reserva;
    END sp_crear_reserva;

    -- sp_liquidacion_mensual
    PROCEDURE sp_liquidacion_mensual(
        p_anio            IN NUMBER,
        p_mes             IN NUMBER,
        p_id_alojamiento  IN NUMBER DEFAULT NULL
    ) IS
        v_reg c_liquidacion_alojamientos%ROWTYPE;
        v_contador_procesados NUMBER := 0;
        v_gran_total_bruto    NUMBER(14,2) := 0;
        v_gran_total_comision NUMBER(14,2) := 0;
        v_gran_total_neto     NUMBER(14,2) := 0;
        v_id_liq              NUMBER;
    BEGIN
        IF p_anio IS NULL OR p_mes IS NULL THEN
            RAISE_APPLICATION_ERROR(-20015, 'sp_liquidacion_mensual: Año y mes son parámetros requeridos.');
        END IF;

        IF p_mes NOT BETWEEN 1 AND 12 THEN
            RAISE_APPLICATION_ERROR(-20016, 'sp_liquidacion_mensual: El mes debe estar comprendido entre 1 y 12.');
        END IF;

        DBMS_OUTPUT.PUT_LINE('   TURISMOUQ - REPORTE DE LIQUIDACIÓN MENSUAL MASIVA DE ALOJAMIENTOS');
        DBMS_OUTPUT.PUT_LINE('   PERIODO EVALUADO: ' || LPAD(p_mes, 2, '0') || ' / ' || p_anio);
        DBMS_OUTPUT.PUT_LINE(
            RPAD('ID', 5) || 
            RPAD('ALOJAMIENTO', 28) || 
            RPAD('MUNICIPIO', 14) || 
            LPAD('RES', 5) || 
            LPAD('NOCHES', 7) || 
            LPAD('TOTAL BRUTO', 15) || 
            LPAD('COMISIÓN (10%)', 16) || 
            LPAD('NETO PAGAR', 16)
        );

        OPEN c_liquidacion_alojamientos(p_anio, p_mes, p_id_alojamiento);
        LOOP
            FETCH c_liquidacion_alojamientos INTO v_reg;
            EXIT WHEN c_liquidacion_alojamientos%NOTFOUND;

            v_contador_procesados := v_contador_procesados + 1;
            v_gran_total_bruto    := v_gran_total_bruto + v_reg.total_bruto;
            v_gran_total_comision := v_gran_total_comision + v_reg.comision_plataforma;
            v_gran_total_neto     := v_gran_total_neto + v_reg.monto_neto_alojamiento;

            BEGIN
                SELECT seq_liquidacion_mensual.NEXTVAL INTO v_id_liq FROM dual;
                
                INSERT INTO LiquidacionMensual (
                    id_liquidacion,
                    id_alojamiento,
                    anio,
                    mes,
                    total_reservas,
                    total_noches,
                    total_ingresos_estadia,
                    total_ingresos_servicios,
                    total_bruto,
                    comision_plataforma,
                    monto_neto_alojamiento,
                    fecha_liquidacion,
                    estado
                ) VALUES (
                    v_id_liq,
                    v_reg.id_alojamiento,
                    p_anio,
                    p_mes,
                    v_reg.total_reservas,
                    v_reg.total_noches,
                    v_reg.total_ingresos_estadia,
                    v_reg.total_ingresos_servicios,
                    v_reg.total_bruto,
                    v_reg.comision_plataforma,
                    v_reg.monto_neto_alojamiento,
                    SYSDATE,
                    'LIQUIDADO'
                );
            EXCEPTION
                WHEN DUP_VAL_ON_INDEX THEN
                    UPDATE LiquidacionMensual
                    SET total_reservas           = v_reg.total_reservas,
                        total_noches             = v_reg.total_noches,
                        total_ingresos_estadia   = v_reg.total_ingresos_estadia,
                        total_ingresos_servicios = v_reg.total_ingresos_servicios,
                        total_bruto              = v_reg.total_bruto,
                        comision_plataforma      = v_reg.comision_plataforma,
                        monto_neto_alojamiento   = v_reg.monto_neto_alojamiento,
                        fecha_liquidacion        = SYSDATE,
                        estado                   = 'RELIQUIDADO'
                    WHERE id_alojamiento = v_reg.id_alojamiento
                      AND anio = p_anio
                      AND mes = p_mes;
            END;

            DBMS_OUTPUT.PUT_LINE(
                RPAD(v_reg.id_alojamiento, 5) || 
                RPAD(SUBSTR(v_reg.nombre_alojamiento, 1, 26), 28) || 
                RPAD(SUBSTR(v_reg.nombre_municipio, 1, 12), 14) || 
                LPAD(v_reg.total_reservas, 5) || 
                LPAD(v_reg.total_noches, 7) || 
                LPAD(TO_CHAR(v_reg.total_bruto, '$999,999,990'), 15) || 
                LPAD(TO_CHAR(v_reg.comision_plataforma, '$999,999,990'), 16) || 
                LPAD(TO_CHAR(v_reg.monto_neto_alojamiento, '$999,999,990'), 16)
            );
        END LOOP;
        CLOSE c_liquidacion_alojamientos;

        DBMS_OUTPUT.PUT_LINE(
            RPAD('TOTALES (' || v_contador_procesados || ' ALOJAMIENTOS)', 47) || 
            LPAD(TO_CHAR(v_gran_total_bruto, '$999,999,990'), 22) || 
            LPAD(TO_CHAR(v_gran_total_comision, '$999,999,990'), 16) || 
            LPAD(TO_CHAR(v_gran_total_neto, '$999,999,990'), 16)
        );
    END sp_liquidacion_mensual;

END PKG_TURISMOUQ;
/

-- Creación de la función fn_valor_estadia. Encargado de calcular correctamente
-- el valor cruzando temporadas distinitas dentro de la misma estadía
CREATE OR REPLACE FUNCTION fn_valor_estadia(
    p_id_habitacion IN NUMBER,
    p_fecha_in      IN DATE,
    p_fecha_out     IN DATE
) RETURN NUMBER IS
BEGIN
    RETURN PKG_TURISMOUQ.fn_valor_estadia(p_id_habitacion, p_fecha_in, p_fecha_out);
END fn_valor_estadia;
/

-- Creación del procedimiento sp_crear_reserva, el cual valida la disponibilidad,
-- fechas y capacidad; excepciones propias
CREATE OR REPLACE PROCEDURE sp_crear_reserva(
    p_id_cliente         IN  NUMBER,
    p_id_habitacion      IN  NUMBER,
    p_fecha_checkin      IN  DATE,
    p_fecha_checkout     IN  DATE,
    p_cantidad_huespedes IN  NUMBER,
    p_id_reserva         OUT NUMBER
) IS
BEGIN
    PKG_TURISMOUQ.sp_crear_reserva(
        p_id_cliente, 
        p_id_habitacion, 
        p_fecha_checkin, 
        p_fecha_checkout, 
        p_cantidad_huespedes, 
        p_id_reserva
    );
END sp_crear_reserva;
/

-- Creación del cursor sp_liquidacion_mensual, el cual recorre con parámetros
-- y genera el resultado esperado
CREATE OR REPLACE PROCEDURE sp_liquidacion_mensual(
    p_anio            IN NUMBER,
    p_mes             IN NUMBER,
    p_id_alojamiento  IN NUMBER DEFAULT NULL
) IS
BEGIN
    PKG_TURISMOUQ.sp_liquidacion_mensual(p_anio, p_mes, p_id_alojamiento);
END sp_liquidacion_mensual;
/