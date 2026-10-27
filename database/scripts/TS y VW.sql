-- Crear tablespace propio ts_historico_reservas para almacenar por separado la 
-- información de las reservas históricas mediante la tabla HistoricoReserva.

/*
¿Por qué separar el histórico en un tablespace propio?
Esta separación permite organizar mejor los datos antiguos y diferenciarlos de la
información utilizada en las operaciones actuales del sistema. Además, facilita 
la administración, el mantenimiento y los respaldos de la información histórica.
El datafile se configuró con un tamaño inicial de 50 MB y crecimiento automático
de 25 MB hasta un máximo de 1 GB, lo que permite disponer de espacio adicional 
cuando sea necesario sin tener que aumentar manualmente su tamaño.
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

-- Crear vista materializada de ocupación mensual mv_ocupacion_mensual, para
-- almacenar resultados precalculados sobre la ocupación mensual de los 
-- alojamientos, incluyendo las reservas completadas, las noches ocupadas, los 
-- huéspedes atendidos y los ingresos recibidos. 

/*
¿Por qué se elegió la política REFRESH COMPLETE ON DEMAND?
Se elegió la política REFRESH COMPLETE ON DEMAND porque permite actualizar los 
resultados cuando sea necesario, sin ejecutar el cálculo automáticamente cada 
vez que se registra una reserva o un pago. Aunque la actualización completa 
implica volver a calcular los datos de la vista, esta política facilita su
administración y permite programar las actualizaciones en horarios de menor 
actividad. De esta manera, las consultas gerenciales pueden obtener los 
indicadores desde los resultados almacenados, reduciendo el trabajo de cálculo 
en cada consulta. Como los datos no se actualizan automáticamente, es necesario
ejecutar o programar el refresco para mantener la información al día
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