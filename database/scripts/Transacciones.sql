-- PROYECTO INTEGRADOR: TURISMOUQ - PLATAFORMA DE RESERVAS
-- ASIGNATURA: BASES DE DATOS II
-- Script: Transacciones
-- Entrega 3 del Proyecto

--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED;

-- 1. Secuencias para pago y ReservaServicio
DECLARE
    v_inicio NUMBER;
BEGIN
    BEGIN
        EXECUTE IMMEDIATE 'DROP SEQUENCE seq_pago';
    EXCEPTION
        WHEN OTHERS THEN
            IF 
                SQLCODE <> -2289 THEN RAISE; 
            END IF;
    END;
    SELECT NVL(MAX(id_pago), 0) + 1 INTO v_inicio FROM Pago;
    EXECUTE IMMEDIATE 'CREATE SEQUENCE seq_pago START WITH ' || v_inicio || 
        ' INCREMENT BY 1 NOCACHE';
 
    BEGIN
        EXECUTE IMMEDIATE 'DROP SEQUENCE seq_reserva_servicio';
    EXCEPTION
        WHEN OTHERS THEN
            IF 
                SQLCODE <> -2289 THEN RAISE; 
            END IF;
    END;
    SELECT NVL(MAX(id_reserva_servicio), 0) + 1 INTO v_inicio FROM ReservaServicio;
    EXECUTE IMMEDIATE 'CREATE SEQUENCE seq_reserva_servicio START WITH ' 
        || v_inicio || ' INCREMENT BY 1 NOCACHE';
END;
/

-- 2. Procedimiento transaccional sp_registrar_reserva_pago 
CREATE OR REPLACE PROCEDURE sp_registrar_reserva_pago(
    p_id_cliente IN  NUMBER,
    p_id_habitacion IN  NUMBER,
    p_fecha_checkin IN  DATE,
    p_fecha_checkout IN  DATE,
    p_cantidad_huespedes IN  NUMBER,
    p_metodo_pago IN  VARCHAR2,
    p_id_servicio IN  NUMBER DEFAULT NULL,
    p_cantidad_servicio IN  NUMBER DEFAULT 1,
    p_id_reserva OUT NUMBER,
    p_id_pago OUT NUMBER,
    p_servicio_registrado OUT VARCHAR2
) IS
    e_check_violado   EXCEPTION;
    -- ORA-02290: CHECK violado
    PRAGMA EXCEPTION_INIT(e_check_violado, -2290);   
 
    v_precio_servicio NUMBER(12,2);
    v_valor_servicio  NUMBER(12,2) := 0;
    v_valor_estadia   NUMBER(12,2);
BEGIN
    -- Primer SAVEPOINT: todo lo que sigue se puede deshacer
    SAVEPOINT sp_inicio_transaccion;
 
    -- Crear reserva con habitación, validar fechas, capacidad y disponibilidad
    PKG_TURISMOUQ.sp_crear_reserva(
        p_id_cliente, p_id_habitacion, p_fecha_checkin,
        p_fecha_checkout, p_cantidad_huespedes, p_id_reserva
    );
 
    -- Segundo SAVEPOINT: la reserva ya existe; el servicio es opcional
    SAVEPOINT sp_reserva_creada;
 
    -- Servicio adicional del mismo alojamiento de la habitación
    p_servicio_registrado := 'NO_SOLICITADO';
    IF p_id_servicio IS NOT NULL THEN
        BEGIN
            SELECT s.precio
            INTO v_precio_servicio
            FROM Servicio s
            JOIN Habitacion h ON h.id_alojamiento = s.id_alojamiento
            WHERE s.id_servicio = p_id_servicio
                AND h.id_habitacion = p_id_habitacion;
 
            INSERT INTO ReservaServicio (
                id_reserva_servicio, id_reserva, id_servicio, cantidad, precio_unitario
            ) VALUES (
                seq_reserva_servicio.NEXTVAL, p_id_reserva, p_id_servicio,
                p_cantidad_servicio, v_precio_servicio
            );
 
            v_valor_servicio := p_cantidad_servicio * v_precio_servicio;
            p_servicio_registrado := 'SI';
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- ROLLBACK PARCIAL: solo se descarta el servicio
                ROLLBACK TO sp_reserva_creada;
                v_valor_servicio := 0;
                p_servicio_registrado := 'NO: el servicio no existe o no pertenece al alojamiento de la habitación';
            WHEN e_check_violado THEN
                ROLLBACK TO sp_reserva_creada;
                v_valor_servicio := 0;
                p_servicio_registrado := 'NO: cantidad o precio del servicio inválido';
        END;
    END IF;
 
    -- Realizar el pago por el valor de la estadía (noche por noche) + servicio
    v_valor_estadia := PKG_TURISMOUQ.fn_valor_estadia(
        p_id_habitacion, p_fecha_checkin, p_fecha_checkout
    );
 
    p_id_pago := seq_pago.NEXTVAL;
    INSERT INTO Pago (id_pago, id_reserva, fecha_pago, monto, metodo_pago, estado)
    VALUES (p_id_pago, p_id_reserva, SYSDATE, v_valor_estadia + v_valor_servicio,
            p_metodo_pago, 'EXITOSO');
 
EXCEPTION
    WHEN OTHERS THEN
        -- Falla de reserva o pago: se deshace TODO y se relanza el error
        ROLLBACK TO sp_inicio_transaccion;
        p_id_reserva := NULL;
        p_id_pago    := NULL;
        RAISE;
END sp_registrar_reserva_pago;
/

-- 3. Demostraciones: cada demostración termina con un ROLLBACK para no dejar 
-- datos. Se busca una habitación llibre del 26/12/2026 al 29/12/2026, que 
-- tiene temporada.

-- Primera desmotración: Transacción completa con reserva, servicio y pago
DECLARE
    v_hab NUMBER; v_aloj NUMBER; v_serv NUMBER;
    v_res NUMBER; v_pago NUMBER; v_serv_ok VARCHAR2(200);
    v_n_res NUMBER; v_n_srv NUMBER; v_n_pag NUMBER; v_monto NUMBER;
    v_ci DATE := DATE '2026-12-26';
    v_co DATE := DATE '2026-12-29';
BEGIN
    SELECT MIN(h.id_habitacion) INTO v_hab
    FROM Habitacion h
    WHERE NOT EXISTS (
        SELECT 1 FROM ReservaHabitacion rh JOIN Reserva r ON r.id_reserva = rh.id_reserva
        WHERE rh.id_habitacion = h.id_habitacion
            AND r.estado IN ('PENDIENTE', 'CONFIRMADA', 'COMPLETADA')
            AND rh.fecha_checkin < v_co AND rh.fecha_checkout > v_ci);
    SELECT id_alojamiento INTO v_aloj FROM Habitacion WHERE id_habitacion = v_hab;
    SELECT MIN(id_servicio) INTO v_serv FROM Servicio WHERE id_alojamiento = v_aloj;
 
    DBMS_OUTPUT.PUT_LINE('Primera demostración: reserva, servicio y pago');
    sp_registrar_reserva_pago(1, v_hab, v_ci, v_co, 2, 'TARJETA_CREDITO', 
        v_serv, 2, v_res, v_pago, v_serv_ok);
 
    SELECT COUNT(*) INTO v_n_res FROM Reserva WHERE id_reserva = v_res;
    SELECT COUNT(*) INTO v_n_srv FROM ReservaServicio WHERE id_reserva = v_res;
    SELECT COUNT(*), NVL(SUM(monto), 0) INTO v_n_pag, v_monto FROM Pago WHERE id_reserva = v_res;
 
    DBMS_OUTPUT.PUT_LINE('Habitación usada: ' || v_hab);
    DBMS_OUTPUT.PUT_LINE('Servicio registrado: ' || v_serv_ok);
    DBMS_OUTPUT.PUT_LINE('Reservas / Servicios / Pagos creados: ' || v_n_res || ' / ' || v_n_srv || ' / ' || v_n_pag);
    DBMS_OUTPUT.PUT_LINE('Monto del pago: $' || TO_CHAR(v_monto, '999,999,990.00'));
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('ROLLBACK de la demostración ejecutado.');
END;
/

-- Segunda desmotración: ROLLBACK PARCIAL. El servicio a utilizar es de otro
-- alojamiento, por lo tanto se descarta solo el servicio, pero la reserva y el 
-- pago se quedan
DECLARE
    v_hab NUMBER; v_aloj NUMBER; v_serv NUMBER;
    v_res NUMBER; v_pago NUMBER; v_serv_ok VARCHAR2(200);
    v_n_res NUMBER; v_n_srv NUMBER; v_n_pag NUMBER;
    v_ci DATE := DATE '2026-12-26';
    v_co DATE := DATE '2026-12-29';
BEGIN
    SELECT MIN(h.id_habitacion) INTO v_hab
    FROM Habitacion h
    WHERE NOT EXISTS (
        SELECT 1 FROM ReservaHabitacion rh JOIN Reserva r ON r.id_reserva = rh.id_reserva
        WHERE rh.id_habitacion = h.id_habitacion
            AND r.estado IN ('PENDIENTE', 'CONFIRMADA', 'COMPLETADA')
            AND rh.fecha_checkin < v_co AND rh.fecha_checkout > v_ci);
    SELECT id_alojamiento INTO v_aloj FROM Habitacion WHERE id_habitacion = v_hab;
    SELECT MIN(id_servicio) INTO v_serv FROM Servicio WHERE id_alojamiento <> v_aloj;
 
    DBMS_OUTPUT.PUT_LINE('Segunda demostración: ROLLBACK PARCIAL con servicio de otro alojamiento');
    sp_registrar_reserva_pago(1, v_hab, v_ci, v_co, 2, 'PSE',
                              v_serv, 1, v_res, v_pago, v_serv_ok);
 
    SELECT COUNT(*) INTO v_n_res FROM Reserva WHERE id_reserva = v_res;
    SELECT COUNT(*) INTO v_n_srv FROM ReservaServicio WHERE id_reserva = v_res;
    SELECT COUNT(*) INTO v_n_pag FROM Pago WHERE id_reserva = v_res;
 
    DBMS_OUTPUT.PUT_LINE('Servicio registrado: ' || v_serv_ok);
    DBMS_OUTPUT.PUT_LINE('Reservas / Servicios / Pagos creados: ' || v_n_res || ' / ' || v_n_srv || ' / ' || v_n_pag);
    DBMS_OUTPUT.PUT_LINE('Resultado esperado: 1 / 0 / 1 -> solo se deshizo el servicio');
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('ROLLBACK de la demostración ejecutado.');
END;
/

-- Tercera demostración: ROLLBACK TOTAL. Fechas de 2030 sin temporada definida: 
-- la reserva se crea, pero fn_valor_estadia falla al calcular el pago mostrando 
-- el error -20006 y se deshace TODO.
DECLARE
    v_res NUMBER; v_pago NUMBER; v_serv_ok VARCHAR2(200);
    v_n_rh NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('Tercera demostración: ROLLBACK TOTAL. el pago no se puede calcular');
    BEGIN
        sp_registrar_reserva_pago(1, 1, DATE '2030-01-10', DATE '2030-01-13', 2, 'EFECTIVO',
                                  NULL, 1, v_res, v_pago, v_serv_ok);
        DBMS_OUTPUT.PUT_LINE('ERROR: la transacción no debía terminar bien.');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error capturado: ' || SQLERRM);
    END;
 
    SELECT COUNT(*) INTO v_n_rh FROM ReservaHabitacion
    WHERE id_habitacion = 1 AND fecha_checkin = DATE '2030-01-10';
    DBMS_OUTPUT.PUT_LINE('Filas de ReservaHabitacion que quedaron: ' || v_n_rh);
    ROLLBACK;
END;
/