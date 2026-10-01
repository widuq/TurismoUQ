-- 1. Consulta de Ocupación por Municipio y Mes utilizando PIVOT

-- Primero se calcula el total de días/horas reservados de las habitaciones completadas y 
-- Se pivotea los números de los meses (1 al 12) para transformarlos en columnas.

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


-- 2. Consulta de Ingresos por municipio, tipo de alojamiento y temporada con ROLLUP o CUBE,
-- usando GROUPING para distinguir los subtotales.


-- Se coloca etiquetas para mostrar subtotales
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
    
    SUM(p.monto) AS total_ingresos
    
    --Conectando las tablas con JOINS
FROM Municipio m
JOIN Alojamiento a ON m.id_municipio = a.id_municipio
JOIN TipoAlojamiento ta ON a.id_tipo_alojamiento = ta.id_tipo_alojamiento
JOIN Habitacion h ON a.id_alojamiento = h.id_alojamiento
JOIN Tarifa tar ON h.id_habitacion = tar.id_habitacion
JOIN Temporada t ON tar.id_temporada = t.id_temporada
JOIN ReservaHabitacion rh ON h.id_habitacion = rh.id_habitacion
JOIN Reserva r ON rh.id_reserva = r.id_reserva
JOIN Pago p ON r.id_reserva = p.id_reserva

-- Filtra resultados donde la reserva se ha completado 
WHERE r.estado = 'COMPLETADA' 

--Rollup agrupa los datos de derecha a izquierda y calcula los subtotales:
GROUP BY ROLLUP(m.nombre, ta.nombre, t.nombre)
ORDER BY GROUPING(m.nombre) ASC, m.nombre, GROUPING(ta.nombre) ASC, ta.nombre;




-- 3. Consulta de Los 3 alojamientos de mayor ingreso dentro de cada municipio (RANK con PARTITION BY).

-- Crea una tabla temporal para calcular y clasificar los ingresos antes de aplicar el filtro final.
WITH IngresosAlojamiento AS (
    SELECT 
        m.nombre AS municipio, a.nombre AS alojamiento, SUM(p.monto) AS ingresos_totales,
        RANK() OVER (
            -- Agrupa el conteo por municipio, reiniciando el ranking en 1 para cada nuevo municipio.
            PARTITION BY m.id_municipio 
            ORDER BY SUM(p.monto) DESC
        ) AS ranking
  
  --Conectando las tablas con JOINS 
    FROM Municipio m
    JOIN Alojamiento a ON m.id_municipio = a.id_municipio
    JOIN Habitacion h ON a.id_alojamiento = h.id_alojamiento
    JOIN ReservaHabitacion rh ON h.id_habitacion = rh.id_habitacion
    JOIN Reserva r ON rh.id_reserva = r.id_reserva
    JOIN Pago p ON r.id_reserva = p.id_reserva
    
    -- Filtro para tomar las reservas completadas
    WHERE r.estado = 'COMPLETADA' --AND p.estado = 'EXITOSO'
    
    -- Agrupa los ingresos totales por cada hotel
    GROUP BY m.id_municipio, m.nombre, a.id_alojamiento, a.nombre
)

-- Muestra los resultados finales para cada municipio (TOP 3)
SELECT 
    municipio, ranking, alojamiento, ingresos_totales
FROM IngresosAlojamiento
WHERE ranking <= 3
ORDER BY municipio, ranking;



-- 4. Consulta de Variación de ingresos mes contra mes (LAG). 

WITH IngresosMensuales AS (
    SELECT 
        EXTRACT(YEAR FROM r.fecha_reserva) AS anio,
        EXTRACT(MONTH FROM r.fecha_reserva) AS mes,
        SUM(p.monto) AS ingresos_mes
    FROM Reserva r
    JOIN Pago p ON r.id_reserva = p.id_reserva
    WHERE r.estado = 'COMPLETADA'
    GROUP BY 
        EXTRACT(YEAR FROM r.fecha_reserva),
        EXTRACT(MONTH FROM r.fecha_reserva)
)
SELECT 
    anio, mes, ingresos_mes,
    
    -- Obtiene el ingreso del mes anterior
    LAG(ingresos_mes, 1, 0) OVER (
        ORDER BY anio, mes
    ) AS ingresos_mes_anterior,
    
    -- Variación absoluta en pesos ($)
    ingresos_mes - LAG(ingresos_mes, 1, 0) OVER (
        ORDER BY anio, mes
    ) AS variacion_monto,
    
    -- Variación porcentual (%)
    ROUND(
        ( (ingresos_mes - LAG(ingresos_mes, 1, 0) OVER (ORDER BY anio, mes)) 
          / NULLIF(LAG(ingresos_mes, 1, 0) OVER (ORDER BY anio, mes), 0) 
        ) * 100, 2
    ) AS variacion_porcentual
FROM IngresosMensuales
ORDER BY anio, mes;


-- Consulta de temporadas en BD
SELECT * 
FROM Temporada 
ORDER BY anio, fecha_inicio;
