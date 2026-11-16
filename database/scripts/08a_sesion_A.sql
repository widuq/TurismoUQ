-- Proyecto Integrador: TurismoUQ - Plataforma de Reservas
-- Asignatura: Bases de Datos II
-- Script 08a: Sesión A para probar la concurrencia
-- Entrega 3 del Proyecto

--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED;

-- Primer escenario de concurrencia antes de crear el procedimiento encargado de 
-- bloquear la fila cuando se desea realizar una reserva, usando la sesión A
-- Habitación 1, del 10 al 15 de mayo de 2029.

-- Crear reserva para el primer escenario con la Sesión A
DECLARE v_id NUMBER;
BEGIN
    sp_crear_reserva(1, 1, DATE '2029-05-10', DATE '2029-05-15', 2, v_id);
    DBMS_OUTPUT.PUT_LINE('Sesión A: reserva ' || v_id || ' creada.');
END;
/


-- Primero realizar COMMIT con la Sesión A
COMMIT;


-- Segundo escenario de concurrencia después de crear el procedimiento sp_crear_reserva_segura 
-- encargado de bloquear la fila cuando se desea realizar una reserva, usando la sesión A
-- Habitación 1, del 10 al 15 de mayo de 2029.

-- Crear reserva para el segundo escenario con la Sesión A
DECLARE v_id NUMBER;
BEGIN
    sp_crear_reserva_segura(1, 1, DATE '2029-05-10', DATE '2029-05-15', 2, v_id);
    DBMS_OUTPUT.PUT_LINE('Sesión A: reserva ' || v_id || ' creada.');
END;
/


-- Igual que en el escenario anterior, ejecutamos primero el COMMIT en la Sesión A
-- Después de realizar el COMMIT en la Sesión A se desbloquea la Sesión B
COMMIT;