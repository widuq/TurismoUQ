--------------------------------------------------------------------------------
-- PROYECTO INTEGRADOR: TURISMOUQ - PLATAFORMA DE RESERVAS
-- ASIGNATURA: BASES DE DATOS II
-- SCRIPT 03: CONSULTAS DE ANÁLISIS - ENTREGA 1 (CORREGIDO)
--------------------------------------------------------------------------------

-- ------------------------------------------------------------
-- 1. OCUPACIÓN POR MUNICIPIO Y MES CON PIVOT
-- Objetivo: Determinar el total de noches reservadas por municipio
-- distribuidas en columnas de enero a diciembre para reservas COMPLETADAS.
-- ------------------------------------------------------------

SELECT *
FROM (
    SELECT 
        m.nombre AS municipio,
        EXTRACT(MONTH FROM rh.fecha_checkin) AS mes,
        (rh.fecha_checkout - rh.fecha_checkin) AS noches_reservadas
    
    --Conectando las tablas con JOINS
    FROM Municipio m
    JOIN Alojamiento a ON m.id_municipio = a.id_municipio
    JOIN Habitacion h ON a.id_alojamiento = h.id_alojamiento
    JOIN ReservaHabitacion rh ON h.id_habitacion = rh.id_habitacion
    JOIN Reserva r ON rh.id_reserva = r.id_reserva
    WHERE r.estado = 'COMPLETADA'
)

-- El PIVOT toma los meses que normalmente salen como filas hacia abajo y los convierte 
-- en columnas horizontales, para mostrar el total de noches reservadas en una tabla.
PIVOT (
    SUM(noches_reservadas)
    FOR mes IN (
        1  AS Enero, 
        2  AS Febrero, 
        3  AS Marzo, 
        4  AS Abril,
        5  AS Mayo, 
        6  AS Junio, 
        7  AS Julio, 
        8  AS Agosto,
        9  AS Septiembre, 
        10 AS Octubre, 
        11 AS Noviembre, 
        12 AS Diciembre
    )
)
ORDER BY municipio;


-- ------------------------------------------------------------
-- 2. INGRESOS POR MUNICIPIO, TIPO DE ALOJAMIENTO Y TEMPORADA CON ROLLUP
-- Objetivo: Totalizar ingresos con subtotales jerárquicos usando GROUPING.
-- Corrección aplicada:
--   - Se asocia TEMPORADA mediante condición de fecha (r.fecha_checkin BETWEEN t.fecha_inicio AND t.fecha_fin),
--     evitando el producto cartesiano con TARIFA que multiplicaba los datos x 7.8.
--   - Se pre-agregan los pagos por reserva (estado 'EXITOSO') para no duplicar montos con ReservaHabitacion.
-- ------------------------------------------------------------


WITH PagosPorReserva AS (
    SELECT 
        id_reserva,
        SUM(monto) AS total_pagado
    FROM Pago
    WHERE estado = 'EXITOSO'
    GROUP BY id_reserva
),
AlojamientoPorReserva AS (
    SELECT 
        rh.id_reserva,
        h.id_alojamiento
    FROM ReservaHabitacion rh
    JOIN Habitacion h ON rh.id_habitacion = h.id_habitacion
    GROUP BY rh.id_reserva, h.id_alojamiento
)
SELECT 
    CASE 
        WHEN GROUPING(m.nombre) = 1 THEN 'TOTAL GENERAL' 
        ELSE m.nombre 
    END AS municipio,
    
    CASE 
        WHEN GROUPING(ta.nombre) = 1 AND GROUPING(m.nombre) = 0 THEN 'SUBTOTAL MUNICIPIO' 
        WHEN GROUPING(ta.nombre) = 1 THEN 'N/A'
        ELSE ta.nombre 
    END AS tipo_alojamiento,
    
    CASE 
        WHEN GROUPING(t.nombre) = 1 AND GROUPING(ta.nombre) = 0 THEN 'SUBTOTAL TIPO' 
        WHEN GROUPING(t.nombre) = 1 THEN 'N/A'
        ELSE t.nombre 
    END AS temporada,
    
    SUM(pr.total_pagado) AS total_ingresos
    
FROM Municipio m
JOIN Alojamiento a ON m.id_municipio = a.id_municipio
JOIN TipoAlojamiento ta ON a.id_tipo_alojamiento = ta.id_tipo_alojamiento
JOIN AlojamientoPorReserva apr ON a.id_alojamiento = apr.id_alojamiento
JOIN Reserva r ON apr.id_reserva = r.id_reserva
JOIN Temporada t ON r.fecha_checkin BETWEEN t.fecha_inicio AND t.fecha_fin
JOIN PagosPorReserva pr ON r.id_reserva = pr.id_reserva
WHERE r.estado = 'COMPLETADA'
GROUP BY ROLLUP(m.nombre, ta.nombre, t.nombre)
ORDER BY 
    GROUPING(m.nombre) ASC, m.nombre, 
    GROUPING(ta.nombre) ASC, ta.nombre, 
    GROUPING(t.nombre) ASC, t.nombre;


-- ------------------------------------------------------------
-- 3. LOS 3 ALOJAMIENTOS DE MAYOR INGRESO DENTRO DE CADA MUNICIPIO (RANK CON PARTITION BY)
-- Objetivo: Identificar el Top 3 de alojamientos más rentables por municipio.
-- Corrección aplicada:
--   - Se desacopla la agregación de Pago respecto a ReservaHabitacion para no multiplicar
--     los montos en reservas con múltiples habitaciones.
--   - Se consideran únicamente pagos con estado 'EXITOSO' para reservas 'COMPLETADA'.
-- ------------------------------------------------------------
WITH PagosPorReserva AS (
    SELECT 
        id_reserva,
        SUM(monto) AS total_pagado
    FROM Pago
    WHERE estado = 'EXITOSO'
    GROUP BY id_reserva
),
AlojamientoPorReserva AS (
    SELECT 
        rh.id_reserva,
        h.id_alojamiento
    FROM ReservaHabitacion rh
    JOIN Habitacion h ON rh.id_habitacion = h.id_habitacion
    GROUP BY rh.id_reserva, h.id_alojamiento
),
IngresosAlojamiento AS (
    SELECT 
        m.nombre AS municipio,
        a.nombre AS alojamiento,
        SUM(pr.total_pagado) AS ingresos_totales,
        RANK() OVER (
            PARTITION BY m.id_municipio 
            ORDER BY SUM(pr.total_pagado) DESC
        ) AS ranking
    FROM Municipio m
    JOIN Alojamiento a ON m.id_municipio = a.id_municipio
    JOIN AlojamientoPorReserva apr ON a.id_alojamiento = apr.id_alojamiento
    JOIN Reserva r ON apr.id_reserva = r.id_reserva
    JOIN PagosPorReserva pr ON r.id_reserva = pr.id_reserva
    WHERE r.estado = 'COMPLETADA'
    GROUP BY m.id_municipio, m.nombre, a.id_alojamiento, a.nombre
)
SELECT 
    municipio, 
    ranking, 
    alojamiento, 
    ingresos_totales
FROM IngresosAlojamiento
WHERE ranking <= 3
ORDER BY municipio, ranking;


-- ------------------------------------------------------------
-- 4. VARIACIÓN DE INGRESOS MES CONTRA MES (LAG)
-- Objetivo: Medir el crecimiento o contracción intermensual de la facturación.
-- ------------------------------------------------------------
WITH PagosPorReserva AS (
    SELECT 
        id_reserva,
        SUM(monto) AS total_pagado
    FROM Pago
    WHERE estado = 'EXITOSO'
    GROUP BY id_reserva
),
IngresosMensuales AS (
    SELECT 
        EXTRACT(YEAR FROM r.fecha_reserva) AS anio,
        EXTRACT(MONTH FROM r.fecha_reserva) AS mes,
        SUM(pr.total_pagado) AS ingresos_mes
    FROM Reserva r
    JOIN PagosPorReserva pr ON r.id_reserva = pr.id_reserva
    WHERE r.estado = 'COMPLETADA'
    GROUP BY 
        EXTRACT(YEAR FROM r.fecha_reserva),
        EXTRACT(MONTH FROM r.fecha_reserva)
)
SELECT 
    anio, 
    mes, 
    ingresos_mes,
    LAG(ingresos_mes, 1, 0) OVER (ORDER BY anio, mes) AS ingresos_mes_anterior,
    ingresos_mes - LAG(ingresos_mes, 1, 0) OVER (ORDER BY anio, mes) AS variacion_monto,
    ROUND(
        ( (ingresos_mes - LAG(ingresos_mes, 1, 0) OVER (ORDER BY anio, mes)) 
          / NULLIF(LAG(ingresos_mes, 1, 0) OVER (ORDER BY anio, mes), 0) 
        ) * 100, 2
    ) AS variacion_porcentual
FROM IngresosMensuales
ORDER BY anio, mes;


-- ------------------------------------------------------------
-- 5. CONSULTA PARAMETRIZADA CON VARIABLES DE ENLACE PARA RANGO DE FECHAS
-- Objetivo: Facturación y volumen de reservas por alojamiento en un rango dinámico.
-- Corrección aplicada:
--   - Se reemplaza la variable de sustitución léxica (&) por variables de enlace nativas de Oracle (:b_fecha_inicio, :b_fecha_fin).
--   - Se elimina la duplicación de pagos al desvincular ReservaHabitacion del cálculo de Pago.
-- ------------------------------------------------------------

-- Declaración y asignación de variables de enlace (ejecutar en SQL*Plus / SQL Developer):
VARIABLE b_fecha_inicio VARCHAR2(10);
VARIABLE b_fecha_fin VARCHAR2(10);

EXEC :b_fecha_inicio := '2025-01-01';
EXEC :b_fecha_fin := '2025-12-31';

WITH PagosPorReserva AS (
    SELECT 
        id_reserva,
        SUM(monto) AS total_pagado
    FROM Pago
    WHERE estado = 'EXITOSO'
    GROUP BY id_reserva
),
AlojamientoPorReserva AS (
    SELECT 
        rh.id_reserva,
        h.id_alojamiento
    FROM ReservaHabitacion rh
    JOIN Habitacion h ON rh.id_habitacion = h.id_habitacion
    GROUP BY rh.id_reserva, h.id_alojamiento
)
SELECT 
    m.nombre AS municipio,
    a.nombre AS alojamiento,
    COUNT(DISTINCT r.id_reserva) AS total_reservas,
    SUM(pr.total_pagado) AS ingresos_totales
FROM Municipio m
JOIN Alojamiento a ON m.id_municipio = a.id_municipio
JOIN AlojamientoPorReserva apr ON a.id_alojamiento = apr.id_alojamiento
JOIN Reserva r ON apr.id_reserva = r.id_reserva
JOIN PagosPorReserva pr ON r.id_reserva = pr.id_reserva
WHERE r.estado = 'COMPLETADA'
  AND r.fecha_reserva BETWEEN TO_DATE(:b_fecha_inicio, 'YYYY-MM-DD') 
                          AND TO_DATE(:b_fecha_fin, 'YYYY-MM-DD')
GROUP BY m.id_municipio, m.nombre, a.id_alojamiento, a.nombre
ORDER BY ingresos_totales DESC;


-- ------------------------------------------------------------
-- 6. UNPIVOT DE INGRESOS POR NIVEL DE TEMPORADA
-- Objetivo: Demostrar transformación PIVOT a columnas y reversión con UNPIVOT a filas.
-- Corrección aplicada:
--   - Temporada se relaciona por fechas de check-in (r.fecha_checkin BETWEEN t.fecha_inicio AND t.fecha_fin).
--   - Se elimina el cruce erróneo con Tarifa y se pre-agregan los pagos exitosos.
-- ------------------------------------------------------------
WITH PagosPorReserva AS (
    SELECT 
        id_reserva,
        SUM(monto) AS total_pagado
    FROM Pago
    WHERE estado = 'EXITOSO'
    GROUP BY id_reserva
),
IngresosPorTemporada AS (
    SELECT 
        t.anio,
        EXTRACT(MONTH FROM r.fecha_checkin) AS mes,
        t.nivel AS temporada,
        SUM(pr.total_pagado) AS total_ingresos
    FROM Reserva r
    JOIN PagosPorReserva pr ON r.id_reserva = pr.id_reserva
    JOIN Temporada t ON r.fecha_checkin BETWEEN t.fecha_inicio AND t.fecha_fin
    WHERE r.estado = 'COMPLETADA'
    GROUP BY 
        t.anio,
        EXTRACT(MONTH FROM r.fecha_checkin),
        t.nivel
),
MatrizPivotada AS (
    SELECT *
    FROM IngresosPorTemporada
    PIVOT (
        SUM(total_ingresos)
        FOR temporada IN ('ALTA' AS ALTA, 'MEDIA' AS MEDIA, 'BAJA' AS BAJA)
    )
)
SELECT 
    anio,
    mes,
    tipo_temporada,
    ingresos
FROM MatrizPivotada
UNPIVOT (
    ingresos FOR tipo_temporada IN (ALTA, MEDIA, BAJA)
)
ORDER BY anio, mes, tipo_temporada;


-- ------------------------------------------------------------
-- 7. CONSULTA GERENCIAL LIBRE: ANÁLISIS DE PÉRDIDAS POR CANCELACIÓN
-- Pregunta de negocio:
--   ¿Cuáles alojamientos registran mayor número de reservas canceladas
--   y cuál es el monto de pagos involucrados en dichas cancelaciones?
-- Corrección aplicada:
--   - Se desacopla ReservaHabitacion del cálculo de Pago para evitar duplicar montos.
--   - Se utiliza LEFT JOIN con NVL para incluir alojamientos con cancelaciones aún sin pagos registrados.
-- ------------------------------------------------------------
WITH PagosPorReserva AS (
    SELECT 
        id_reserva,
        SUM(monto) AS total_pagado
    FROM Pago
    GROUP BY id_reserva
),
AlojamientoPorReserva AS (
    SELECT 
        rh.id_reserva,
        h.id_alojamiento
    FROM ReservaHabitacion rh
    JOIN Habitacion h ON rh.id_habitacion = h.id_habitacion
    GROUP BY rh.id_reserva, h.id_alojamiento
)
SELECT 
    m.nombre AS municipio,
    a.nombre AS alojamiento,
    COUNT(DISTINCT r.id_reserva) AS total_reservas_canceladas,
    NVL(SUM(pr.total_pagado), 0) AS ingresos_afectados_cancelacion
FROM Municipio m
JOIN Alojamiento a ON m.id_municipio = a.id_municipio
JOIN AlojamientoPorReserva apr ON a.id_alojamiento = apr.id_alojamiento
JOIN Reserva r ON apr.id_reserva = r.id_reserva
LEFT JOIN PagosPorReserva pr ON r.id_reserva = pr.id_reserva
WHERE r.estado = 'CANCELADA'
GROUP BY m.nombre, a.nombre
ORDER BY total_reservas_canceladas DESC, ingresos_afectados_cancelacion DESC;


