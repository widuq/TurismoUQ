-- PROYECTO INTEGRADOR: TURISMOUQ - PLATAFORMA DE RESERVAS
-- ASIGNATURA: BASES DE DATOS II
-- Script: Sesión B para probar la concurrencia
-- Entrega 3 del Proyecto

--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED;

-- Primer escenario de concurrencia antes de crear el procedimiento encargado de 
-- bloquear la fila cuando se desea realizar una reserva, usando la sesión B
-- Habitación 1, del 12 al 17 de mayo de 2029 (Fecha que se solapa con las 
-- fechas de la Sesión A).

-- Crear reserva para el primer escenario con la Sesión B y fechas solapadas
DECLARE v_id NUMBER;
BEGIN
    sp_crear_reserva(2, 1, DATE '2029-05-12', DATE '2029-05-17', 2, v_id);
    DBMS_OUTPUT.PUT_LINE('Sesión B: reserva ' || v_id || ' creada.');
END;
/

-- Luego realizar COMMIT con la Sesión B
COMMIT;

-- Segundo escenario de concurrencia después de crear el procedimiento sp_crear_reserva_segura 
-- encargado de bloquear la fila cuando se desea realizar una reserva, usando la sesión B
-- Habitación 1, del 12 al 17 de mayo de 2029 (Fecha que se solapa con las fechas
-- de la Sesión A).

-- Crear reserva para el segundo escenario con la Sesión B, pero aquí se queda esperando porque la fila se
-- encuentra bloqueada
DECLARE v_id NUMBER;
BEGIN
    sp_crear_reserva_segura(2, 1, DATE '2029-05-12', DATE '2029-05-17', 2, v_id);
    DBMS_OUTPUT.PUT_LINE('Sesión B: reserva ' || v_id || ' creada.');
END;
/

-- Después de que se ejecute el COMMIT en la sesión, el resultado esperado en la
-- Sesión B es "ORA-20001: "Habitación no disponible", porque ahora sí ve la 
-- reserva confirmada de la sesión A. Entonces en la Sesión B ejecutamos ROLLBACK"
ROLLBACK;