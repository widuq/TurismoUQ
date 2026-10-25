--------------------------------------------------------------------------------
-- PROYECTO INTEGRADOR: TURISMOUQ - PLATAFORMA DE RESERVAS
-- ASIGNATURA: BASES DE DATOS II
-- SCRIPT 04: CAPA PL/SQL, DISPARADORES Y ALMACENAMIENTO - ENTREGA 2
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- -- Ejecutar lo siguiente conectado como un usuario con permisos SYSTEM 
-- GRANT CREATE PROCEDURE TO TURISMO;
-- GRANT CREATE TRIGGER TO TURISMO;
-- GRANT CREATE TABLESPACE TO TURISMO;
-- GRANT CREATE MATERIALIZED VIEW TO TURISMO;
-- GRANT CREATE VIEW TO TURISMO;

-- -- Permite al usuario consultar tablas en transacciones y manejar vistas materializadas
-- GRANT QUERY REWRITE TO TURISMO;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------



SET SERVEROUTPUT ON SIZE UNLIMITED;

----------------------------------------------------------------------------------
-- SECCIÓN 0: ESTRUCTURAS DE SOPORTE PARA AUDITORÍA Y LIQUIDACIÓN
--------------------------------------------------------------------------------

-- 0.1 Tabla para registrar la auditoría de cambios sobre la tabla TARIFA
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

COMMENT ON COLUMN AuditoriaTarifa.id_auditoria IS 'Identificador secuencial del evento de auditoría.';
COMMENT ON COLUMN AuditoriaTarifa.id_tarifa IS 'Identificador de la tarifa afectada.';
COMMENT ON COLUMN AuditoriaTarifa.id_habitacion IS 'Habitación a la que pertenece la tarifa.';
COMMENT ON COLUMN AuditoriaTarifa.id_temporada IS 'Temporada de la tarifa.';
COMMENT ON COLUMN AuditoriaTarifa.precio_anterior IS 'Precio por noche antes de la modificación.';
COMMENT ON COLUMN AuditoriaTarifa.precio_nuevo IS 'Precio por noche posterior a la modificación.';
COMMENT ON COLUMN AuditoriaTarifa.operacion IS 'Tipo de operación DML: INSERT, UPDATE o DELETE.';
COMMENT ON COLUMN AuditoriaTarifa.usuario IS 'Usuario de base de datos que ejecutó la sentencia.';
COMMENT ON COLUMN AuditoriaTarifa.fecha_cambio IS 'Fecha y hora exacta en la que se realizó la operación.';

-- Secuencia para la tabla de auditoría
BEGIN
    EXECUTE IMMEDIATE 'DROP SEQUENCE seq_auditoria_tarifa';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/
CREATE SEQUENCE seq_auditoria_tarifa START WITH 1 INCREMENT BY 1 NOCACHE;


-- 0.2 Tabla para persistir los resultados del proceso masivo de liquidación mensual
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


--------------------------------------------------------------------------------
-- 1. PAQUETE PL/SQL: PKG_TURISMOUQ
--------------------------------------------------------------------------------

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

    -- Declaración del procedimiento de liquidación masiva
    PROCEDURE sp_liquidacion_mensual(
        p_anio            IN NUMBER,
        p_mes             IN NUMBER,
        p_id_alojamiento  IN NUMBER DEFAULT NULL
    );

END PKG_TURISMOUQ;
/


--------------------------------------------------------------------------------
-- CUERPO DEL PAQUETE: PKG_TURISMOUQ
--------------------------------------------------------------------------------

CREATE OR REPLACE PACKAGE BODY PKG_TURISMOUQ AS

    -- ------------------------------------------------------------
    -- 1.1 fn_valor_estadia
    -- ------------------------------------------------------------
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


    -- ------------------------------------------------------------
    -- 1.2 sp_crear_reserva
    -- ------------------------------------------------------------
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


    -- ------------------------------------------------------------
    -- 1.3 sp_liquidacion_mensual
    -- ------------------------------------------------------------
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

        DBMS_OUTPUT.PUT_LINE('--------------------------------------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE('   TURISMOUQ - REPORTE DE LIQUIDACIÓN MENSUAL MASIVA DE ALOJAMIENTOS');
        DBMS_OUTPUT.PUT_LINE('   PERIODO EVALUADO: ' || LPAD(p_mes, 2, '0') || ' / ' || p_anio);
        DBMS_OUTPUT.PUT_LINE('--------------------------------------------------------------------------------');
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
        DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------------------------');

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

        DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE(
            RPAD('TOTALES (' || v_contador_procesados || ' ALOJAMIENTOS)', 47) || 
            LPAD(TO_CHAR(v_gran_total_bruto, '$999,999,990'), 22) || 
            LPAD(TO_CHAR(v_gran_total_comision, '$999,999,990'), 16) || 
            LPAD(TO_CHAR(v_gran_total_neto, '$999,999,990'), 16)
        );
        DBMS_OUTPUT.PUT_LINE('--------------------------------------------------------------------------------');
    END sp_liquidacion_mensual;

END PKG_TURISMOUQ;
/


-- --------------------------------------------------------------------------------
-- 1.4 SINÓNIMOS / ENVOLTORIOS INDIVIDUALES (STANDALONE WRAPPERS)
-- --------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_valor_estadia(
    p_id_habitacion IN NUMBER,
    p_fecha_in      IN DATE,
    p_fecha_out     IN DATE
) RETURN NUMBER IS
BEGIN
    RETURN PKG_TURISMOUQ.fn_valor_estadia(p_id_habitacion, p_fecha_in, p_fecha_out);
END fn_valor_estadia;
/

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

CREATE OR REPLACE PROCEDURE sp_liquidacion_mensual(
    p_anio            IN NUMBER,
    p_mes             IN NUMBER,
    p_id_alojamiento  IN NUMBER DEFAULT NULL
) IS
BEGIN
    PKG_TURISMOUQ.sp_liquidacion_mensual(p_anio, p_mes, p_id_alojamiento);
END sp_liquidacion_mensual;
/


--------------------------------------------------------------------------------
-- 2. DISPARADOR A NIVEL DE SENTENCIA: AUDITORÍA DE CAMBIOS SOBRE TARIFA
--------------------------------------------------------------------------------

CREATE OR REPLACE TRIGGER trg_auditoria_tarifa_sentencia
FOR INSERT OR UPDATE OR DELETE ON Tarifa
COMPOUND TRIGGER

    TYPE r_auditoria IS RECORD (
        id_tarifa        Tarifa.id_tarifa%TYPE,
        id_habitacion    Tarifa.id_habitacion%TYPE,
        id_temporada     Tarifa.id_temporada%TYPE,
        precio_anterior  Tarifa.precio_noche%TYPE,
        precio_nuevo     Tarifa.precio_noche%TYPE,
        operacion        VARCHAR2(20)
    );
    TYPE t_auditoria_lista IS TABLE OF r_auditoria INDEX BY PLS_INTEGER;
    v_cambios t_auditoria_lista;

    BEFORE STATEMENT IS
    BEGIN
        v_cambios.DELETE;
    END BEFORE STATEMENT;

    AFTER EACH ROW IS
        v_idx PLS_INTEGER;
    BEGIN
        v_idx := v_cambios.COUNT + 1;

        IF INSERTING THEN
            v_cambios(v_idx).id_tarifa       := :NEW.id_tarifa;
            v_cambios(v_idx).id_habitacion   := :NEW.id_habitacion;
            v_cambios(v_idx).id_temporada    := :NEW.id_temporada;
            v_cambios(v_idx).precio_anterior := NULL;
            v_cambios(v_idx).precio_nuevo    := :NEW.precio_noche;
            v_cambios(v_idx).operacion       := 'INSERT';
        ELSIF UPDATING THEN
            v_cambios(v_idx).id_tarifa       := :NEW.id_tarifa;
            v_cambios(v_idx).id_habitacion   := :NEW.id_habitacion;
            v_cambios(v_idx).id_temporada    := :NEW.id_temporada;
            v_cambios(v_idx).precio_anterior := :OLD.precio_noche;
            v_cambios(v_idx).precio_nuevo    := :NEW.precio_noche;
            v_cambios(v_idx).operacion       := 'UPDATE';
        ELSIF DELETING THEN
            v_cambios(v_idx).id_tarifa       := :OLD.id_tarifa;
            v_cambios(v_idx).id_habitacion   := :OLD.id_habitacion;
            v_cambios(v_idx).id_temporada    := :OLD.id_temporada;
            v_cambios(v_idx).precio_anterior := :OLD.precio_noche;
            v_cambios(v_idx).precio_nuevo    := NULL;
            v_cambios(v_idx).operacion       := 'DELETE';
        END IF;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_usuario VARCHAR2(50);
        v_fecha   DATE;
    BEGIN
        v_usuario := SYS_CONTEXT('USERENV', 'SESSION_USER');
        v_fecha   := SYSDATE;

        FOR i IN 1 .. v_cambios.COUNT LOOP
            INSERT INTO AuditoriaTarifa (
                id_auditoria,
                id_tarifa,
                id_habitacion,
                id_temporada,
                precio_anterior,
                precio_nuevo,
                operacion,
                usuario,
                fecha_cambio
            ) VALUES (
                seq_auditoria_tarifa.NEXTVAL,
                v_cambios(i).id_tarifa,
                v_cambios(i).id_habitacion,
                v_cambios(i).id_temporada,
                v_cambios(i).precio_anterior,
                v_cambios(i).precio_nuevo,
                v_cambios(i).operacion,
                v_usuario,
                v_fecha
            );
        END LOOP;
    END AFTER STATEMENT;

END trg_auditoria_tarifa_sentencia;
/


--------------------------------------------------------------------------------
-- 3. DISPARADOR A NIVEL DE FILA: IMPEDIR SOLAPAMIENTO DE RESERVAS
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_verificar_solape_habitacion(
    p_id_reserva_hab IN NUMBER,
    p_id_habitacion  IN NUMBER,
    p_checkin        IN DATE,
    p_checkout       IN DATE
) RETURN NUMBER IS
    PRAGMA AUTONOMOUS_TRANSACTION;
    v_coincidencias NUMBER := 0;
BEGIN
    SELECT COUNT(*)
    INTO v_coincidencias
    FROM ReservaHabitacion rh
    JOIN Reserva r ON rh.id_reserva = r.id_reserva
    WHERE rh.id_habitacion = p_id_habitacion
      AND r.estado IN ('PENDIENTE', 'CONFIRMADA', 'COMPLETADA')
      AND (p_id_reserva_hab IS NULL OR rh.id_reserva_habitacion <> p_id_reserva_hab)
      AND TRUNC(p_checkin) < TRUNC(rh.fecha_checkout)
      AND TRUNC(p_checkout) > TRUNC(rh.fecha_checkin);

    RETURN v_coincidencias;
END fn_verificar_solape_habitacion;
/

CREATE OR REPLACE TRIGGER trg_no_solape_reserva_hab
BEFORE INSERT OR UPDATE OF id_habitacion, fecha_checkin, fecha_checkout ON ReservaHabitacion
FOR EACH ROW
DECLARE
    v_solapamientos NUMBER;
BEGIN
    IF TRUNC(:NEW.fecha_checkout) <= TRUNC(:NEW.fecha_checkin) THEN
        RAISE_APPLICATION_ERROR(
            -20002, 
            'Disparador de Fila: La fecha de checkout (' || TO_CHAR(:NEW.fecha_checkout, 'YYYY-MM-DD') || 
            ') debe ser estrictamente posterior a la fecha de checkin (' || 
            TO_CHAR(:NEW.fecha_checkin, 'YYYY-MM-DD') || ').'
        );
    END IF;

    v_solapamientos := fn_verificar_solape_habitacion(
        :NEW.id_reserva_habitacion,
        :NEW.id_habitacion,
        :NEW.fecha_checkin,
        :NEW.fecha_checkout
    );

    IF v_solapamientos > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20010, 
            'Disparador de Fila [-20010]: Solapamiento detectado. La habitación ' || :NEW.id_habitacion || 
            ' ya se encuentra reservada en el rango ' || TO_CHAR(:NEW.fecha_checkin, 'YYYY-MM-DD') || 
            ' a ' || TO_CHAR(:NEW.fecha_checkout, 'YYYY-MM-DD') || ' por otra reserva activa.'
        );
    END IF;
END trg_no_solape_reserva_hab;
/


--------------------------------------------------------------------------------
-- 4. TABLESPACE PROPIO PARA EL HISTÓRICO DE RESERVAS
--------------------------------------------------------------------------------

/*
--------------------------------------------------------------------------------
JUSTIFICACIÓN TÉCNICA Y DE ARQUITECTURA: POR QUÉ SEPARAR EL HISTÓRICO EN UN TABLESPACE PROPIO
--------------------------------------------------------------------------------
1. AISLAMIENTO DE I/O Y RENDIMIENTO OLTP vs. OLAP:
   En un sistema de reservas en producción, las tablas Reserva y ReservaHabitacion sufren alta
   concurrencia de operaciones INSERT y UPDATE (transaccionales, OLTP). Si los datos históricos
   antiguos (2024 y anteriores) comparten los mismos datafiles, las consultas analíticas pesadas,
   reportes gerenciales y barridos completos de tabla (Full Table Scans) compiten directamente
   por los mismos bloques de disco y saturan el Buffer Cache (SGA), degradando drásticamente
   el tiempo de respuesta de las reservas de los clientes actuales.

2. ESTRATEGIA DE BACKUP Y RECUPERACIÓN DIFERENCIADA (RMAN Y READ ONLY):
   Los datos históricos de reservas de años culminados son de naturaleza inmutable (Read-Mostly o
   Read-Only). Al segregarlos en el tablespace TS_HISTORICO_RESERVAS, éste puede declararse como
   READ ONLY:
       ALTER TABLESPACE ts_historico_reservas READ ONLY;
   Al ser de sólo lectura, Oracle RMAN únicamente necesita respaldarlo una sola vez, excluyéndolo
   de los respaldos incrementales nocturnos diarios. Esto reduce en más de un 60 % la ventana de
   backup, ahorra espacio en cinta/disco de respaldo y disminuye sustancialmente el RTO (Recovery Time Objective).

3. GESTIÓN DEL CICLO DE VIDA DE LA INFORMACIÓN (ILM - INFORMATION LIFECYCLE MANAGEMENT):
   Permite implementar una estrategia de almacenamiento por niveles (Storage Tiering):
   - El Tablespace Transaccional principal reside en almacenamiento de ultra-alta velocidad (NVMe/SSD).
   - El Tablespace Histórico puede ubicarse en discos magnéticos estándar (HDD/NL-SAS o NAS/Cloud),
     reduciendo significativamente los costos operativos de almacenamiento sin comprometer el desempeño operativo.

4. CONTROL DE FRAGMENTACIÓN Y MANTENIMIENTO SIMPLIFICADO:
   Las purgas masivas o archivados dentro del tablespace principal generan fragmentación interna y huecos
   en los bloques (High Water Mark elevado). Al utilizar un tablespace dedicado, se puede transportar
   (Transportable Tablespace), reubicar o truncar sin impactar la integridad ni los índices del tablespace en línea.
--------------------------------------------------------------------------------
*/

BEGIN
    EXECUTE IMMEDIATE '
        CREATE TABLESPACE ts_historico_reservas
        DATAFILE ''ts_historico_reservas01.dbf'' SIZE 50M
        AUTOEXTEND ON NEXT 25M MAXSIZE 1G
        EXTENT MANAGEMENT LOCAL
        SEGMENT SPACE MANAGEMENT AUTO';
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Nota Tablespace: ' || SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE HistoricoReserva CASCADE CONSTRAINTS PURGE';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE '
        CREATE TABLE HistoricoReserva (
            id_historico        NUMBER(10)   NOT NULL,
            id_reserva          NUMBER(10)   NOT NULL,
            id_cliente          NUMBER(10)   NOT NULL,
            id_habitacion       NUMBER(10)   NOT NULL,
            fecha_reserva       DATE         NOT NULL,
            fecha_checkin       DATE         NOT NULL,
            fecha_checkout      DATE         NOT NULL,
            estado              VARCHAR2(20) NOT NULL,
            monto_total         NUMBER(12,2) NOT NULL,
            fecha_archivado     DATE DEFAULT SYSDATE NOT NULL,
            usuario_archivador  VARCHAR2(50) DEFAULT USER NOT NULL,
            
            CONSTRAINT pk_historico_reserva PRIMARY KEY (id_historico)
        ) TABLESPACE ts_historico_reservas';
EXCEPTION
    WHEN OTHERS THEN
        EXECUTE IMMEDIATE '
            CREATE TABLE HistoricoReserva (
                id_historico        NUMBER(10)   NOT NULL,
                id_reserva          NUMBER(10)   NOT NULL,
                id_cliente          NUMBER(10)   NOT NULL,
                id_habitacion       NUMBER(10)   NOT NULL,
                fecha_reserva       DATE         NOT NULL,
                fecha_checkin       DATE         NOT NULL,
                fecha_checkout      DATE         NOT NULL,
                estado              VARCHAR2(20) NOT NULL,
                monto_total         NUMBER(12,2) NOT NULL,
                fecha_archivado     DATE DEFAULT SYSDATE NOT NULL,
                usuario_archivador  VARCHAR2(50) DEFAULT USER NOT NULL,
                
                CONSTRAINT pk_historico_reserva PRIMARY KEY (id_historico)
            )';
END;
/

COMMENT ON TABLE HistoricoReserva IS
'Tabla para almacenamiento de reservas históricas archivadas en el tablespace TS_HISTORICO_RESERVAS.';


--------------------------------------------------------------------------------
-- 5. VISTA MATERIALIZADA DE OCUPACIÓN MENSUAL (CONVENCIÓN mv_)
--------------------------------------------------------------------------------

/*
--------------------------------------------------------------------------------
JUSTIFICACIÓN TÉCNICA DE LA POLÍTICA DE REFRESCO: POR QUÉ REFRESH COMPLETE ON DEMAND
--------------------------------------------------------------------------------
1. EVITAR SOBRECOSTO Y PENALIZACIÓN EN TRANSACCIONES OLTP (FAST ON COMMIT NO DESEABLE):
   Una política FAST ON COMMIT requeriría la creación previa de Materialized View Logs (MLOG$)
   sobre las tablas base Reserva, ReservaHabitacion y Pago. Cada reserva o pago realizado por
   un cliente obligaría a Oracle a calcular deltas e intentar refrescar la vista materializada
   dentro de la misma transacción del cliente. En un entorno de reservas concurrentes (más de 25.000
   reservas), esto genera bloqueos de fila (enqueue contention), incrementa la latencia del commit
   y satura los Redo Logs innecesariamente.

2. NATURALEZA AGREGADA Y GERENCIAL DE LA MÉTRICA:
   La ocupación mensual es un indicador consolidado de planeación y análisis estratégico (OLAP).
   La gerencia y los encargados de alojamiento evalúan los resultados del mes culminado o del cierre
   del día anterior. Ningún tomador de decisiones requiere que la ocupación mensual cambie en tiempo
   real a la milésima de segundo de cada clic de un usuario en el portal web.

3. PROGRAMACIÓN EFICIENTE EN VENTANAS DE BAJO TRÁFICO (BATCH SCHEDULING):
   La política ON DEMAND permite automatizar el refresco mediante un Job de DBMS_SCHEDULER durante
   la ventana nocturna (ej. 01:00 a.m. diariamente o el primer día de cada mes):
       EXEC DBMS_MVIEW.REFRESH(''MV_OCUPACION_MENSUAL'', ''C'');
   Esto garantiza costo CERO durante el horario de atención al cliente y provee a los tableros
   de Business Intelligence tiempos de respuesta sub-segundo, leyendo directamente los datos precalculados.
--------------------------------------------------------------------------------
*/

BEGIN
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_ocupacion_mensual';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

CREATE MATERIALIZED VIEW mv_ocupacion_mensual
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
WITH PagosPorReserva AS (
    SELECT 
        id_reserva,
        SUM(monto) AS total_pagado
    FROM Pago
    WHERE estado = 'EXITOSO'
    GROUP BY id_reserva
),
ResumenPorReserva AS (
    SELECT 
        rh.id_reserva,
        h.id_alojamiento,
        MIN(rh.fecha_checkin) AS fecha_checkin_res,
        SUM(rh.fecha_checkout - rh.fecha_checkin) AS noches_reserva,
        SUM(rh.cantidad_huespedes) AS huespedes_reserva
    FROM ReservaHabitacion rh
    JOIN Habitacion h ON rh.id_habitacion = h.id_habitacion
    GROUP BY rh.id_reserva, h.id_alojamiento
)
SELECT 
    EXTRACT(YEAR FROM rpr.fecha_checkin_res) AS anio,
    EXTRACT(MONTH FROM rpr.fecha_checkin_res) AS mes,
    m.id_municipio,
    m.nombre AS nombre_municipio,
    a.id_alojamiento,
    a.nombre AS nombre_alojamiento,
    ta.nombre AS tipo_alojamiento,
    COUNT(DISTINCT r.id_reserva) AS total_reservas_completadas,
    SUM(rpr.noches_reserva) AS total_noches_ocupadas,
    SUM(rpr.huespedes_reserva) AS total_huespedes_atendidos,
    NVL(SUM(pr.total_pagado), 0) AS total_ingresos_hospedaje
FROM Municipio m
JOIN Alojamiento a ON m.id_municipio = a.id_municipio
JOIN TipoAlojamiento ta ON a.id_tipo_alojamiento = ta.id_tipo_alojamiento
JOIN ResumenPorReserva rpr ON a.id_alojamiento = rpr.id_alojamiento
JOIN Reserva r ON rpr.id_reserva = r.id_reserva
LEFT JOIN PagosPorReserva pr ON r.id_reserva = pr.id_reserva
WHERE r.estado = 'COMPLETADA'
GROUP BY 
    EXTRACT(YEAR FROM rpr.fecha_checkin_res),
    EXTRACT(MONTH FROM rpr.fecha_checkin_res),
    m.id_municipio,
    m.nombre,
    a.id_alojamiento,
    a.nombre,
    ta.nombre;

-- Índices sobre la vista materializada para acelerar las consultas analíticas
CREATE INDEX idx_mv_ocup_periodo ON mv_ocupacion_mensual (anio, mes);
CREATE INDEX idx_mv_ocup_alojamiento ON mv_ocupacion_mensual (id_alojamiento);
CREATE INDEX idx_mv_ocup_municipio ON mv_ocupacion_mensual (id_municipio);

COMMENT ON MATERIALIZED VIEW mv_ocupacion_mensual IS
'Vista materializada con pre-agregación de ocupación mensual por alojamiento y municipio.';


--------------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA Y DEMOSTRACIÓN (TEST SUITE)
--------------------------------------------------------------------------------

-- ------------------------------------------------------------
-- PRUEBA 1: fn_valor_estadia con cruce de múltiples temporadas
-- Caso: Habitación 1 reservada del 25 de febrero al 05 de marzo de 2025.
--       Atraviesa Temporada Alta 2025 (hasta el 28 de febrero)
--       y Temporada Media 2025 (desde el 01 de marzo).
-- ------------------------------------------------------------
PROMPT --------------------------------------------------------------------------------;
PROMPT PRUEBA 1: CÁLCULO DE ESTADÍA MULTI-TEMPORADA (fn_valor_estadia)
PROMPT --------------------------------------------------------------------------------;

DECLARE
    v_id_hab     NUMBER := 1;
    v_checkin    DATE := DATE '2025-02-25';
    v_checkout   DATE := DATE '2025-03-05';
    v_total_dias NUMBER;
    v_valor      NUMBER(12,2);
BEGIN
    v_total_dias := v_checkout - v_checkin;
    v_valor := PKG_TURISMOUQ.fn_valor_estadia(v_id_hab, v_checkin, v_checkout);

    DBMS_OUTPUT.PUT_LINE('Habitación ID : ' || v_id_hab);
    DBMS_OUTPUT.PUT_LINE('Fecha Checkin : ' || TO_CHAR(v_checkin, 'YYYY-MM-DD'));
    DBMS_OUTPUT.PUT_LINE('Fecha Checkout: ' || TO_CHAR(v_checkout, 'YYYY-MM-DD'));
    DBMS_OUTPUT.PUT_LINE('Noches totales: ' || v_total_dias || ' noches (3 en Temporada Alta + 5 en Temporada Media)');
    DBMS_OUTPUT.PUT_LINE('Valor calculado por fn_valor_estadia: $' || TO_CHAR(v_valor, '999,999,990.00'));
END;
/


-- ------------------------------------------------------------
-- PRUEBA 2: sp_crear_reserva exitosa
-- Caso: Registrar una reserva válida para el cliente 1 en habitación 1.
-- ------------------------------------------------------------
PROMPT --------------------------------------------------------------------------------;
PROMPT PRUEBA 2: CREACIÓN EXITOSA DE RESERVA (sp_crear_reserva)
PROMPT --------------------------------------------------------------------------------;

DECLARE
    v_id_reserva_nueva NUMBER;
BEGIN
    sp_crear_reserva(
        p_id_cliente         => 1,
        p_id_habitacion      => 1,
        p_fecha_checkin      => DATE '2027-01-10',
        p_fecha_checkout     => DATE '2027-01-15',
        p_cantidad_huespedes => 2,
        p_id_reserva         => v_id_reserva_nueva
    );

    DBMS_OUTPUT.PUT_LINE('>> ÉXITO: Reserva creada correctamente con ID: ' || v_id_reserva_nueva);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('>> Rollback de prueba ejecutado satisfactoriamente.');
END;
/


-- ------------------------------------------------------------
-- PRUEBA 3: Excepciones de sp_crear_reserva vía RAISE_APPLICATION_ERROR
-- ------------------------------------------------------------
PROMPT --------------------------------------------------------------------------------;
PROMPT PRUEBA 3: VALIDACIÓN DE EXCEPCIONES EN sp_crear_reserva
PROMPT --------------------------------------------------------------------------------;

-- 3A. Checkout anterior o igual al Checkin (-20002)
DECLARE
    v_id_res NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('-- Probando Checkout <= Checkin...');
    sp_crear_reserva(1, 1, DATE '2027-05-10', DATE '2027-05-08', 2, v_id_res);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('>> Captura esperada: ' || SQLERRM);
END;
/

-- 3B. Capacidad máxima excedida (-20003)
DECLARE
    v_id_res NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('-- Probando Capacidad Excedida (solicitando 20 personas en una habitación sencilla)...');
    sp_crear_reserva(1, 1, DATE '2027-06-01', DATE '2027-06-05', 20, v_id_res);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('>> Captura esperada: ' || SQLERRM);
END;
/

-- 3C. Habitación no disponible por fechas solapadas (-20001)
DECLARE
    v_id_res1 NUMBER;
    v_id_res2 NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('-- Probando Habitación No Disponible (solapamiento directo)...');
    
    -- Pedir 1 huésped (la habitación 2 es individual)
    sp_crear_reserva(1, 2, DATE '2027-08-10', DATE '2027-08-20', 1, v_id_res1);
    
    -- Intentar solapar fechas (15 al 25 de agosto) con 1 huésped
    sp_crear_reserva(2, 2, DATE '2027-08-15', DATE '2027-08-25', 1, v_id_res2);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('>> Captura esperada: ' || SQLERRM);
        ROLLBACK;
END;
/


-- ------------------------------------------------------------
-- PRUEBA 4: Proceso masivo de liquidación mensual con cursor explícito parametrizado
-- ------------------------------------------------------------
PROMPT --------------------------------------------------------------------------------;
PROMPT PRUEBA 4: LIQUIDACIÓN MENSUAL MASIVA (sp_liquidacion_mensual)
PROMPT --------------------------------------------------------------------------------;

BEGIN
    PKG_TURISMOUQ.sp_liquidacion_mensual(p_anio => 2025, p_mes => 7);
END;
/


-- ------------------------------------------------------------
-- PRUEBA 5: Disparador a nivel de sentencia (Auditoría de cambios sobre TARIFA)
-- ------------------------------------------------------------
PROMPT --------------------------------------------------------------------------------;
PROMPT PRUEBA 5: DISPARADOR DE SENTENCIA - AUDITORÍA SOBRE TARIFA
PROMPT --------------------------------------------------------------------------------;

DECLARE
    v_conteo_antes   NUMBER;
    v_conteo_despues NUMBER;
    v_precio_orig    NUMBER(12,2);
BEGIN
    SELECT COUNT(*) INTO v_conteo_antes FROM AuditoriaTarifa;
    SELECT precio_noche INTO v_precio_orig FROM Tarifa WHERE id_tarifa = 1;

    UPDATE Tarifa
    SET precio_noche = precio_noche + 15000
    WHERE id_tarifa = 1;

    SELECT COUNT(*) INTO v_conteo_despues FROM AuditoriaTarifa;

    DBMS_OUTPUT.PUT_LINE('Registros en AuditoriaTarifa antes : ' || v_conteo_antes);
    DBMS_OUTPUT.PUT_LINE('Registros en AuditoriaTarifa después: ' || v_conteo_despues);

    FOR r IN (
        SELECT id_auditoria, id_tarifa, precio_anterior, precio_nuevo, operacion, usuario, fecha_cambio
        FROM AuditoriaTarifa
        WHERE id_tarifa = 1
        ORDER BY id_auditoria DESC
        FETCH FIRST 1 ROWS ONLY
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('>> Última auditoría: Tarifa ' || r.id_tarifa || 
                             ' | Anterior: $' || r.precio_anterior || 
                             ' | Nuevo: $' || r.precio_nuevo || 
                             ' | Operación: ' || r.operacion || 
                             ' | Usuario: ' || r.usuario || 
                             ' | Fecha: ' || TO_CHAR(r.fecha_cambio, 'YYYY-MM-DD HH24:MI:SS'));
    END LOOP;

    UPDATE Tarifa SET precio_noche = v_precio_orig WHERE id_tarifa = 1;
    COMMIT;
END;
/


-- ------------------------------------------------------------
-- PRUEBA 6: Disparador a nivel de fila (Impedir solape en ReservaHabitacion)
-- ------------------------------------------------------------
PROMPT --------------------------------------------------------------------------------;
PROMPT PRUEBA 6: DISPARADOR DE FILA - IMPEDIR SOLAPE EN RESERVAHABITACION
PROMPT --------------------------------------------------------------------------------;

DECLARE
    v_nuevo_id_res NUMBER;
    v_nuevo_id_rh  NUMBER;
BEGIN
    SELECT NVL(MAX(id_reserva), 0) + 9999 INTO v_nuevo_id_res FROM Reserva;
    SELECT NVL(MAX(id_reserva_habitacion), 0) + 9999 INTO v_nuevo_id_rh FROM ReservaHabitacion;

    -- Se inserta y confirma la reserva base
    INSERT INTO Reserva VALUES (v_nuevo_id_res, 1, SYSDATE, DATE '2028-03-01', DATE '2028-03-10', 'CONFIRMADA');
    INSERT INTO ReservaHabitacion VALUES (v_nuevo_id_rh, v_nuevo_id_res, 5, DATE '2028-03-01', DATE '2028-03-10', 2);
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Insertando reserva solapada para probar el disparador de fila trg_no_solape_reserva_hab...');
    
    -- Intento de inserción de reserva solapada (05 al 15 de marzo de 2028 sobre habitación 5)
    INSERT INTO ReservaHabitacion VALUES (v_nuevo_id_rh + 1, v_nuevo_id_res, 5, DATE '2028-03-05', DATE '2028-03-15', 2);
    
    DBMS_OUTPUT.PUT_LINE('ERROR: El disparador no bloqueó el solapamiento.');
    
    -- Limpieza en caso de fallo
    DELETE FROM ReservaHabitacion WHERE id_reserva = v_nuevo_id_res;
    DELETE FROM Reserva WHERE id_reserva = v_nuevo_id_res;
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('>> Éxito: El disparador de fila bloqueó el solape correctamente.');
        DBMS_OUTPUT.PUT_LINE('>> Mensaje capturado: ' || SQLERRM);
        
        -- Limpieza de la reserva base de prueba
        DELETE FROM ReservaHabitacion WHERE id_reserva = v_nuevo_id_res;
        DELETE FROM Reserva WHERE id_reserva = v_nuevo_id_res;
        COMMIT;
END;
/


-- ------------------------------------------------------------
-- PRUEBA 7: Consulta y refresco de la Vista Materializada
-- ------------------------------------------------------------
PROMPT --------------------------------------------------------------------------------;
PROMPT PRUEBA 7: VISTA MATERIALIZADA - CONSULTA Y REFRESCO
PROMPT --------------------------------------------------------------------------------;

BEGIN
    DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');
    DBMS_OUTPUT.PUT_LINE('>> Vista Materializada MV_OCUPACION_MENSUAL refrescada exitosamente.');
END;
/

SELECT 
    anio, 
    mes, 
    nombre_municipio, 
    nombre_alojamiento, 
    total_reservas_completadas, 
    total_noches_ocupadas, 
    total_huespedes_atendidos, 
    TO_CHAR(total_ingresos_hospedaje, '$999,999,990') AS ingresos_hospedaje
FROM mv_ocupacion_mensual
WHERE anio = 2025 AND mes = 7
ORDER BY total_ingresos_hospedaje DESC
FETCH FIRST 5 ROWS ONLY;