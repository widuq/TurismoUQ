-- Crear el disparador a nivel de sentencia: Auditoría de cambios sobre tarifa,
-- es el encargado de registrar quién, cuándo, valor anterior y nuevo
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

-- Crear disparador a nivel de fila, es el encargado de impedir solamientos de 
-- reservas
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
