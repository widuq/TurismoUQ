-- PROYECTO INTEGRADOR: TURISMOUQ - PLATAFORMA DE RESERVAS
-- ASIGNATURA: BASES DE DATOS II
-- Script: Índices
-- Entrega 3 del Proyecto

--------------------------------------------------------------------------------

-- Consulta 1: Historial de un cliente durante un año
-- Sin índice recorre toda la tabla Reserva (25.000 filas) para encontrar las
-- reservas de un solo cliente.

-- Plan de ejecución ANTES del índice
EXPLAIN PLAN FOR
SELECT id_reserva, estado, fecha_checkin
FROM Reserva
WHERE id_cliente = 1234
  AND fecha_checkin BETWEEN DATE '2025-01-01' AND DATE '2025-12-31';

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY);

-- Crear índice B-tree compuesto, el cual ubica al cliente y filtra las fechas dentro 
-- del mismo índice
CREATE INDEX idx_reserva_cliente_checkin
ON Reserva (id_cliente, fecha_checkin);

-- Plan de ejecución DESPUÉS del índice
EXPLAIN PLAN FOR
SELECT id_reserva, estado, fecha_checkin
FROM Reserva
WHERE id_cliente = 1234
  AND fecha_checkin BETWEEN DATE '2025-01-01' AND DATE '2025-12-31';

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY);

-- Consulta 2: Reservas creadas en un día específico
-- La columna fecha_reserva incluye la hora, por eso se usa TRUNC. Al aplicar 
-- una función a la columna, un índice normal sobre fecha_reserva no se puede
-- usar y se recorre toda la tabla Reserva.

-- Plan de ejecución ANTES del índice
EXPLAIN PLAN FOR
SELECT id_reserva, id_cliente, estado
FROM Reserva
WHERE TRUNC(fecha_reserva) = DATE '2025-07-15';

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY);

-- Crear índice BASADO EN FUNCIÓN, encargado de guardar el resultado calculado de 
-- TRUNC(fecha_reserva)
CREATE INDEX fx_reserva_dia
ON Reserva (TRUNC(fecha_reserva));

-- Plan de ejecución DESPUÉS del índice
EXPLAIN PLAN FOR
SELECT id_reserva, id_cliente, estado
FROM Reserva
WHERE TRUNC(fecha_reserva) = DATE '2025-07-15';

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY);

-- Consulta 3: Disponibilidad de una habitación en un rango de fechas
-- Es la misma consulta que usan sp_crear_reserva y el disparador de solape en
-- cada reserva nueva. Sin índice recorre las todas las filas de ReservaHabitacion.

-- Plan de ejecución ANTES del índice
EXPLAIN PLAN FOR
SELECT id_reserva_habitacion, id_reserva
FROM ReservaHabitacion
WHERE id_habitacion = 5
    AND fecha_checkin < DATE '2025-07-10'
    AND fecha_checkout > DATE '2025-07-05';

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY);

-- Crear índice B-tree compuesto, el cual ubica la habitación y evalúa las dos fechas 
-- dentro del mismo índice
CREATE INDEX idx_reshab_habitacion_fechas
ON ReservaHabitacion (id_habitacion, fecha_checkin, fecha_checkout);

-- Plan de ejecución DESPUÉS del índice
EXPLAIN PLAN FOR
SELECT id_reserva_habitacion, id_reserva
FROM ReservaHabitacion
WHERE id_habitacion = 5
  AND fecha_checkin < DATE '2025-07-10'
  AND fecha_checkout > DATE '2025-07-05';

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY);

-- Consulta donde el índice no ayuda: Reservas con estado COMPLETADA
-- Gran parte de las reservas están COMPLETADAS
-- La columna estado tiene pocos valores distintos, por eso es buena opción un
-- índice BITMAP, pero el filtro devuelve casi toda la tabla.

-- Plan de ejecución ANTES del índice
EXPLAIN PLAN FOR
SELECT id_reserva, id_cliente, fecha_checkin, fecha_checkout
FROM Reserva
WHERE estado = 'COMPLETADA';

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY);

-- Crear índice BITMAP sobre estado
CREATE BITMAP INDEX bx_reserva_estado
ON Reserva (estado);

-- Plan de ejecución DESPUÉS del índice: se sigue recorriendo toda
-- la tabla porque leer casi todas las filas por el índice cuesta más
EXPLAIN PLAN FOR
SELECT id_reserva, id_cliente, fecha_checkin, fecha_checkout
FROM Reserva
WHERE estado = 'COMPLETADA';

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY);

-- Plan forzando el uso del índice a pesar de que el costo es mayor
EXPLAIN PLAN FOR
SELECT /*+ INDEX(r bx_reserva_estado) */ id_reserva, id_cliente, fecha_checkin, fecha_checkout
FROM Reserva r
WHERE estado = 'COMPLETADA';

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY);


-- Borramos el índice porque no aporta mucho y el costo es bastante
DROP INDEX bx_reserva_estado;

-- Verificamos que índices han quedado creados en el proyecto para utilizar
SELECT i.index_name, i.index_type, COUNT(c.column_name) AS columnas
FROM user_indexes i
JOIN user_ind_columns c ON c.index_name = i.index_name
WHERE i.index_name IN ('IDX_RESERVA_CLIENTE_CHECKIN', 'FX_RESERVA_DIA', 'IDX_RESHAB_HABITACION_FECHAS')
GROUP BY i.index_name, i.index_type
ORDER BY i.index_name;