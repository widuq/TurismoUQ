-- PROYECTO INTEGRADOR: TURISMOUQ - PLATAFORMA DE RESERVAS
-- ASIGNATURA: BASES DE DATOS II
-- Script: Tablespace, histórico y vista materializada
-- Entrega 2 del Proyecto

SET SERVEROUTPUT ON SIZE UNLIMITED;

-- Archivos de datos del tablespace
DEFINE v_datafile = 'ts_historico_reservas01.dbf'

/*
¿Por qué separar el histórico en un tablespace propio?
Esta separación permite organizar mejor los datos antiguos y diferenciarlos de la
información utilizada en las operaciones actuales del sistema. Además, facilita 
la administración, el mantenimiento y los respaldos de la información histórica.
El datafile se configuró con un tamaño inicial de 50 MB y crecimiento automático
de 25 MB hasta un máximo de 1 GB, lo que permite disponer de espacio adicional 
cuando sea necesario sin tener que aumentar manualmente su tamaño.
*/

-- 1. Crear tablespace propio ts_historico_reservas para almacenar por separado la 
-- información de las reservas históricas mediante la tabla HistoricoReserva.
DECLARE
    v_existe NUMBER;
BEGIN
    SELECT COUNT(*)
    INTO v_existe
    FROM user_tablespaces
    WHERE tablespace_name = 'TS_HISTORICO_RESERVAS';
    
    IF v_existe = 0 THEN
        EXECUTE IMMEDIATE
            'CREATE TABLESPACE ts_historico_reservas
             DATAFILE ''&v_datafile'' SIZE 50M
             AUTOEXTEND ON NEXT 25M MAXSIZE 1G
             EXTENT MANAGEMENT LOCAL
             SEGMENT SPACE MANAGEMENT AUTO';
        DBMS_OUTPUT.PUT_LINE('Tablespace ts_historico_reservas creado.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Tablespace ts_historico_reservas ya existía.');
    END IF;
END;
/

-- 2. Crear tabla HistoricoReserva. Una fila por reserva archivada. Una reserva
-- puede tener varias habitaciones, por eso se guarda la cantidad y no un 
-- id_habitacion
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE HistoricoReserva CASCADE CONSTRAINTS PURGE';
EXCEPTION
    WHEN OTHERS THEN
        IF
            -- -942 la tabla no existe
            SQLCODE <> -942 THEN RAISE;
        END IF;
END;
/

CREATE TABLE HistoricoReserva (
    id_historico NUMBER(10) NOT NULL,
    id_reserva NUMBER(10) NOT NULL,
    id_cliente NUMBER(10) NOT NULL,
    fecha_reserva DATE NOT NULL,
    fecha_checkin DATE NOT NULL,
    fecha_checkout DATE NOT NULL,
    estado VARCHAR2(20) NOT NULL,
    cantidad_habitaciones NUMBER(4) NOT NULL,
    monto_total NUMBER(12,2) NOT NULL,
    fecha_archivado DATE DEFAULT SYSDATE NOT NULL,
    usuario_archivador VARCHAR2(50) DEFAULT USER NOT NULL,
    CONSTRAINT pk_historico_reserva PRIMARY KEY (id_historico),
    CONSTRAINT uq_historico_id_reserva UNIQUE (id_reserva)
) TABLESPACE ts_historico_reservas;


COMMENT ON TABLE HistoricoReserva IS
'Reservas cerradas (COMPLETADA o CANCELADA) archivadas en el tablespace TS_HISTORICO_RESERVAS';
COMMENT ON COLUMN HistoricoReserva.monto_total IS
'Suma de los pagos EXITOSOS que tenía la reserva al momento de archivarla.';

BEGIN
    EXECUTE IMMEDIATE 'DROP SEQUENCE seq_historico_reserva';
EXCEPTION
    WHEN OTHERS THEN
        IF 
            SQLCODE <> -2289 THEN RAISE; 
        END IF;
END;
/
CREATE SEQUENCE seq_historico_reserva START WITH 1 INCREMENT BY 1 NOCACHE;

-- 3. Crear el procedimiento sp_archivar_reservas, el cual será como un mecanismo
-- de paso hacia la tabla HistoricoReserva. Este se encarga de copiar a 
-- HistoricoReserva las reservas COMPLETADA o CANCELADA cuyo checkout sea anterior
-- a la fecha de corte, y las retira de las tablas Pago, ReservaServicio, 
-- ReservaHabitacion y Reserva.
CREATE OR REPLACE PROCEDURE sp_archivar_reservas(
    p_fecha_corte IN  DATE,
    p_total_archivadas OUT NUMBER
) IS
BEGIN
    IF p_fecha_corte IS NULL THEN
        RAISE_APPLICATION_ERROR(-20020, 'sp_archivar_reservas: La fecha de corte 
            es obligatoria.');
    END IF;
 
    IF TRUNC(p_fecha_corte) > TRUNC(SYSDATE) THEN
        RAISE_APPLICATION_ERROR(-20021, 'sp_archivar_reservas: La fecha de corte 
            no puede ser futura.');
    END IF;
 
    SAVEPOINT sp_inicio_archivado;
 
    INSERT INTO HistoricoReserva (
        id_historico, 
        id_reserva, 
        id_cliente, 
        fecha_reserva,
        fecha_checkin, 
        fecha_checkout, 
        estado,
        cantidad_habitaciones, 
        monto_total
    )
    SELECT seq_historico_reserva.NEXTVAL,
           r.id_reserva, r.id_cliente, r.fecha_reserva,
           r.fecha_checkin, r.fecha_checkout, r.estado,
           (SELECT COUNT(*) FROM ReservaHabitacion rh WHERE rh.id_reserva = r.id_reserva),
           NVL((SELECT SUM(p.monto) FROM Pago p
                WHERE p.id_reserva = r.id_reserva AND p.estado = 'EXITOSO'), 0)
    FROM Reserva r
    WHERE r.estado IN ('COMPLETADA', 'CANCELADA')
        AND TRUNC(r.fecha_checkout) < TRUNC(p_fecha_corte)
        AND NOT EXISTS (SELECT 1 FROM HistoricoReserva h WHERE h.id_reserva = r.id_reserva);

    p_total_archivadas := SQL%ROWCOUNT;
 
    -- Se retiran de las tablas Pago, ReservaServicio, ReservaHabitacion y Reserva
    DELETE FROM Pago
    WHERE id_reserva IN (SELECT h.id_reserva FROM HistoricoReserva h);
 
    DELETE FROM ReservaServicio
    WHERE id_reserva IN (SELECT h.id_reserva FROM HistoricoReserva h);
 
    DELETE FROM ReservaHabitacion
    WHERE id_reserva IN (SELECT h.id_reserva FROM HistoricoReserva h);
 
    DELETE FROM Reserva
    WHERE id_reserva IN (SELECT h.id_reserva FROM HistoricoReserva h);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO sp_inicio_archivado;
        RAISE;
END sp_archivar_reservas;
/

-- 4. Crear vista materializada de ocupación mensual mv_ocupacion_mensual, para
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
    WHEN OTHERS THEN
        IF
            -- -12003: la vista no existe
            SQLCODE <> -12003 THEN RAISE;
        END IF;
END;
/

CREATE MATERIALIZED VIEW mv_ocupacion_mensual
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
WITH Meses AS (
    SELECT 0 AS k FROM dual UNION ALL SELECT 1 FROM dual UNION ALL
    SELECT 2 FROM dual UNION ALL SELECT 3 FROM dual UNION ALL
    SELECT 4 FROM dual UNION ALL SELECT 5 FROM dual UNION ALL
    SELECT 6 FROM dual UNION ALL SELECT 7 FROM dual UNION ALL
    SELECT 8 FROM dual UNION ALL SELECT 9 FROM dual UNION ALL
    SELECT 10 FROM dual UNION ALL SELECT 11 FROM dual
),
TramoMes AS (
    SELECT rh.id_reserva_habitacion,
           rh.id_reserva,
           rh.id_habitacion,
           h.id_alojamiento,
           ADD_MONTHS(TRUNC(rh.fecha_checkin, 'MM'), g.k) AS mes_ini,
           GREATEST(TRUNC(rh.fecha_checkin), ADD_MONTHS(TRUNC(rh.fecha_checkin, 'MM'), g.k)) AS seg_ini,
           LEAST(TRUNC(rh.fecha_checkout), ADD_MONTHS(TRUNC(rh.fecha_checkin, 'MM'), g.k + 1)) AS seg_fin,
           CASE WHEN g.k = 0 THEN rh.cantidad_huespedes ELSE 0 END AS huespedes_tramo
    FROM ReservaHabitacion rh
    JOIN Habitacion h ON rh.id_habitacion = h.id_habitacion
    JOIN Reserva r ON rh.id_reserva = r.id_reserva
    JOIN Meses g
      ON g.k <= MONTHS_BETWEEN(TRUNC(rh.fecha_checkout - 1, 'MM'), TRUNC(rh.fecha_checkin, 'MM'))
    WHERE r.estado = 'COMPLETADA'
),
ValorTramo AS (
    SELECT tm.id_reserva,
           tm.id_alojamiento,
           tm.mes_ini,
           tm.seg_fin - tm.seg_ini AS noches,
           tm.huespedes_tramo,
           NVL(SUM((LEAST(tm.seg_fin, t.fecha_fin + 1) - GREATEST(tm.seg_ini, t.fecha_inicio))
               * tar.precio_noche), 0) AS valor_estadia
    FROM TramoMes tm
    LEFT JOIN Temporada t
        ON t.fecha_inicio < tm.seg_fin
            AND t.fecha_fin + 1 > tm.seg_ini
    LEFT JOIN Tarifa tar
        ON tar.id_habitacion = tm.id_habitacion
            AND tar.id_temporada  = t.id_temporada
    GROUP BY tm.id_reserva_habitacion, tm.id_reserva, tm.id_alojamiento, tm.mes_ini,
             tm.seg_ini, tm.seg_fin, tm.huespedes_tramo
),
Resumen AS (
    SELECT id_alojamiento,
           mes_ini,
           COUNT(DISTINCT id_reserva) AS total_reservas_completadas,
           SUM(noches) AS total_noches_ocupadas,
           SUM(huespedes_tramo) AS total_huespedes_atendidos,
           SUM(valor_estadia) AS total_ingresos_hospedaje
    FROM ValorTramo
    GROUP BY id_alojamiento, mes_ini
),
HabPorAlojamiento AS (
    SELECT id_alojamiento, COUNT(*) AS total_habitaciones
    FROM Habitacion
    GROUP BY id_alojamiento
)
SELECT
    EXTRACT(YEAR FROM rs.mes_ini) AS anio,
    EXTRACT(MONTH FROM rs.mes_ini) AS mes,
    m.id_municipio,
    m.nombre AS nombre_municipio,
    a.id_alojamiento,
    a.nombre AS nombre_alojamiento,
    ta.nombre AS tipo_alojamiento,
    rs.total_reservas_completadas,
    rs.total_noches_ocupadas,
    rs.total_huespedes_atendidos,
    rs.total_ingresos_hospedaje,
    hp.total_habitaciones * (ADD_MONTHS(rs.mes_ini, 1) - rs.mes_ini) AS noches_disponibles,
    ROUND(rs.total_noches_ocupadas * 100 /
        (hp.total_habitaciones * (ADD_MONTHS(rs.mes_ini, 1) - rs.mes_ini)), 2) 
        AS porcentaje_ocupacion
FROM Resumen rs
JOIN Alojamiento a ON rs.id_alojamiento = a.id_alojamiento
JOIN Municipio m ON a.id_municipio = m.id_municipio
JOIN TipoAlojamiento ta ON a.id_tipo_alojamiento = ta.id_tipo_alojamiento
JOIN HabPorAlojamiento hp ON a.id_alojamiento = hp.id_alojamiento;

-- Índices sobre la vista materializada para acelerar las consultas analíticas
CREATE INDEX idx_mv_ocup_periodo ON mv_ocupacion_mensual (anio, mes);
CREATE INDEX idx_mv_ocup_alojamiento ON mv_ocupacion_mensual (id_alojamiento);
CREATE INDEX idx_mv_ocup_municipio ON mv_ocupacion_mensual (id_municipio);

COMMENT ON MATERIALIZED VIEW mv_ocupacion_mensual IS
'Ocupación mensual por alojamiento: noches repartidas por mes, ingresos de hospedaje y porcentaje de ocupación.';