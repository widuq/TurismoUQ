-- PROYECTO INTEGRADOR: TURISMOUQ - PLATAFORMA DE RESERVAS
-- ASIGNATURA: BASES DE DATOS II
-- Script: Concurrencia
-- Entrega 3 del Proyecto

--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED;

-- Crear el procedimiento sp_crear_reserva_segura con SELECT ... FOR UPDATE
-- Antes de verificar disponibilidad bloquea la fila de la habitación. Una 
-- segunda sesión (Sesión B) que pida la misma habitación debe esperar a que la 
-- primera haga COMMIT o ROLLBACK, y ahí verifica la disponibilidad, teniendo
-- la reserva de la primera sesión (Sesión A).
CREATE OR REPLACE PROCEDURE sp_crear_reserva_segura(
    p_id_cliente IN  NUMBER,
    p_id_habitacion IN  NUMBER,
    p_fecha_checkin IN  DATE,
    p_fecha_checkout IN  DATE,
    p_cantidad_huespedes IN  NUMBER,
    p_id_reserva OUT NUMBER
) IS
    e_tiempo_agotado EXCEPTION;
    -- ORA-30006: tiempo de espera agotado
    PRAGMA EXCEPTION_INIT(e_tiempo_agotado, -30006);   
    v_id_hab NUMBER;
BEGIN
    BEGIN
        SELECT id_habitacion
        INTO v_id_hab
        FROM Habitacion
        WHERE id_habitacion = p_id_habitacion
        FOR UPDATE WAIT 30;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(
                PKG_TURISMOUQ.ERR_HABITACION_NO_EXISTE,
                'Error -20005: La habitación con ID ' || p_id_habitacion || ' no existe.'
            );
        WHEN e_tiempo_agotado THEN
            RAISE_APPLICATION_ERROR(
                -20031,
                'Error -20031: La habitación ' || p_id_habitacion ||
                ' está siendo reservada por otra sesión. Intente de nuevo.'
            );
    END;
 
    -- Bloquear la fila, permite que la verificación de disponibilidad sea confiable
    PKG_TURISMOUQ.sp_crear_reserva(
        p_id_cliente, p_id_habitacion, p_fecha_checkin,
        p_fecha_checkout, p_cantidad_huespedes, p_id_reserva
    );
END sp_crear_reserva_segura;
/

-- Luego de crear las reservas en el primer escenario utilizando ambas sesiones, 
-- verificamos que hay doble reserva de la Habitación 1
SELECT a.id_reserva AS reserva_a, b.id_reserva AS reserva_b,
       a.fecha_checkin AS checkin_a, a.fecha_checkout AS checkout_a,
       b.fecha_checkin AS checkin_b, b.fecha_checkout AS checkout_b
FROM ReservaHabitacion a
JOIN ReservaHabitacion b
  ON a.id_habitacion = b.id_habitacion
 AND a.id_reserva_habitacion < b.id_reserva_habitacion
 AND a.fecha_checkin < b.fecha_checkout
 AND a.fecha_checkout > b.fecha_checkin
WHERE a.id_habitacion = 1 AND a.fecha_checkin >= DATE '2029-01-01';

-- Después de haber intentado crear las reservas en el segundo escenario en ambas 
-- sesiones, verificamos que solo haya una reserva para la Habitación 1
SELECT id_reserva_habitacion, id_reserva, id_habitacion, fecha_checkin, fecha_checkout
FROM ReservaHabitacion
WHERE id_habitacion = 1 AND fecha_checkin >= DATE '2029-01-01';

-- Limpiar los datos de los escenarios en ambas sesiones
DELETE FROM ReservaHabitacion WHERE fecha_checkin >= DATE '2029-01-01';
DELETE FROM Reserva WHERE fecha_checkin >= DATE '2029-01-01';
COMMIT;