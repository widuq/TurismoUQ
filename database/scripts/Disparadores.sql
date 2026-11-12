-- PROYECTO INTEGRADOR: TURISMOUQ - PLATAFORMA DE RESERVAS
-- ASIGNATURA: BASES DE DATOS II
-- Script: Disparadores
-- Entrega 2 del Proyecto

--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED;

-- 1. Crear disparador compuesto a nivel de sentencia: Auditoría de cambios sobre tarifa,
-- es el encargado de registrar quién, cuándo, valor anterior y nuevo
CREATE OR REPLACE TRIGGER trg_auditoria_tarifa_sentencia
FOR INSERT OR UPDATE OR DELETE ON Tarifa
COMPOUND TRIGGER

    TYPE r_auditoria IS RECORD (
        id_tarifa Tarifa.id_tarifa%TYPE,
        id_habitacion Tarifa.id_habitacion%TYPE,
        id_temporada Tarifa.id_temporada%TYPE,
        precio_anterior Tarifa.precio_noche%TYPE,
        precio_nuevo Tarifa.precio_noche%TYPE,
        operacion VARCHAR2(20)
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
            v_cambios(v_idx).id_tarifa := :NEW.id_tarifa;
            v_cambios(v_idx).id_habitacion := :NEW.id_habitacion;
            v_cambios(v_idx).id_temporada := :NEW.id_temporada;
            v_cambios(v_idx).precio_anterior := NULL;
            v_cambios(v_idx).precio_nuevo := :NEW.precio_noche;
            v_cambios(v_idx).operacion := 'INSERT';
        ELSIF UPDATING THEN
            v_cambios(v_idx).id_tarifa := :NEW.id_tarifa;
            v_cambios(v_idx).id_habitacion := :NEW.id_habitacion;
            v_cambios(v_idx).id_temporada := :NEW.id_temporada;
            v_cambios(v_idx).precio_anterior := :OLD.precio_noche;
            v_cambios(v_idx).precio_nuevo := :NEW.precio_noche;
            v_cambios(v_idx).operacion := 'UPDATE';
        ELSIF DELETING THEN
            v_cambios(v_idx).id_tarifa := :OLD.id_tarifa;
            v_cambios(v_idx).id_habitacion := :OLD.id_habitacion;
            v_cambios(v_idx).id_temporada := :OLD.id_temporada;
            v_cambios(v_idx).precio_anterior := :OLD.precio_noche;
            v_cambios(v_idx).precio_nuevo := NULL;
            v_cambios(v_idx).operacion := 'DELETE';
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

-- 2. Limpiar la versión anterior del disparador de solape
BEGIN
    EXECUTE IMMEDIATE 'DROP TRIGGER trg_no_solape_reserva_hab';
EXCEPTION
    WHEN OTHERS THEN
        IF 
            -- -4080: el disparador no existe
            SQLCODE <> -4080 THEN RAISE; 
        END IF;   
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP FUNCTION fn_verificar_solape_habitacion';
EXCEPTION
    WHEN OTHERS THEN
        IF 
            -- -4043: el objeto no existe
            SQLCODE <> -4043 THEN RAISE; 
        END IF;   
END;
/


-- 3. Crear disparador compuesto a nivel de fila, es el encargado de impedir 
-- solapamientos en ReservaHabitacion
CREATE OR REPLACE TRIGGER trg_no_solape_reserva_hab
FOR INSERT OR UPDATE OF id_reserva, id_habitacion, fecha_checkin, fecha_checkout 
ON ReservaHabitacion
COMPOUND TRIGGER

    TYPE r_fila IS RECORD (
        id_reserva_habitacion ReservaHabitacion.id_reserva_habitacion%TYPE,
        id_reserva ReservaHabitacion.id_reserva%TYPE,
        id_habitacion ReservaHabitacion.id_habitacion%TYPE,
        fecha_checkin ReservaHabitacion.fecha_checkin%TYPE,
        fecha_checkout ReservaHabitacion.fecha_checkout%TYPE
    );
    TYPE t_filas IS TABLE OF r_fila INDEX BY PLS_INTEGER;
    g_filas t_filas;
 
    BEFORE STATEMENT IS
    BEGIN
        g_filas.DELETE;
    END BEFORE STATEMENT;
    
    AFTER EACH ROW IS
        v_idx PLS_INTEGER;
    BEGIN
        IF TRUNC(:NEW.fecha_checkout) <= TRUNC(:NEW.fecha_checkin) THEN
            RAISE_APPLICATION_ERROR(
                -20002, 'Disparador de Fila: La fecha de checkout (' || 
                TO_CHAR(:NEW.fecha_checkout, 'YYYY-MM-DD') || ') debe ser 
                estrictamente posterior a la fecha de checkin (' || 
                TO_CHAR(:NEW.fecha_checkin, 'YYYY-MM-DD') || ').'
            );
        END IF;
    
        v_idx := g_filas.COUNT + 1;
        g_filas(v_idx).id_reserva_habitacion := :NEW.id_reserva_habitacion;
        g_filas(v_idx).id_reserva := :NEW.id_reserva;
        g_filas(v_idx).id_habitacion := :NEW.id_habitacion;
        g_filas(v_idx).fecha_checkin := :NEW.fecha_checkin;
        g_filas(v_idx).fecha_checkout := :NEW.fecha_checkout;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_reserva_activa NUMBER;
        v_solapamientos  NUMBER;
    BEGIN
        FOR i IN 1 .. g_filas.COUNT LOOP
 
            -- Solo se valida si la reserva de la fila está activa
            SELECT COUNT(*)
            INTO v_reserva_activa
            FROM Reserva r
            WHERE r.id_reserva = g_filas(i).id_reserva
                AND r.estado IN ('PENDIENTE', 'CONFIRMADA', 'COMPLETADA');
            
            IF v_reserva_activa > 0 THEN
                SELECT COUNT(*)
                INTO v_solapamientos
                FROM ReservaHabitacion rh
                JOIN Reserva r ON rh.id_reserva = r.id_reserva
                WHERE rh.id_habitacion = g_filas(i).id_habitacion
                    AND rh.id_reserva_habitacion <> g_filas(i).id_reserva_habitacion
                    AND r.estado IN ('PENDIENTE', 'CONFIRMADA', 'COMPLETADA')
                    AND TRUNC(g_filas(i).fecha_checkin)  < TRUNC(rh.fecha_checkout)
                    AND TRUNC(g_filas(i).fecha_checkout) > TRUNC(rh.fecha_checkin);
                
                IF v_solapamientos > 0 THEN
                    RAISE_APPLICATION_ERROR(
                        -20010, 'Disparador [-20010]: Solapamiento detectado. La habitación ' ||
                        g_filas(i).id_habitacion || ' ya está reservada en el rango ' ||
                        TO_CHAR(g_filas(i).fecha_checkin, 'YYYY-MM-DD') || ' a ' ||
                        TO_CHAR(g_filas(i).fecha_checkout, 'YYYY-MM-DD') ||
                        ' por otra reserva activa.'
                    );
                END IF;
            END IF;
        END LOOP;
    END AFTER STATEMENT;
    
END trg_no_solape_reserva_hab;
/
