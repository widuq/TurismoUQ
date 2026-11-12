-- PROYECTO INTEGRADOR: TURISMOUQ - PLATAFORMA DE RESERVAS
-- ASIGNATURA: BASES DE DATOS II
-- Script: 10 casos de prueba
-- Entrega 2 del Proyecto

SET SERVEROUTPUT ON SIZE UNLIMITED;

-- Casos de prueba y demostración

-- Prueba 1: Cálculo de estadía usando la función fn_valor_estadia con cruce de 
-- múltiples temporadas
-- Caso: Habitación 1 reservada del 25 de febrero al 05 de marzo de 2025.
-- Atraviesa Temporada Alta 2025 (hasta el 28 de febrero)
-- y Temporada Media 2025 (desde el 01 de marzo). 
DECLARE
    v_id_hab NUMBER := 1;
    v_checkin DATE := DATE '2025-02-25';
    v_checkout DATE := DATE '2025-03-05';
    v_total_dias NUMBER;
    v_valor NUMBER(12,2);
BEGIN
    v_total_dias := v_checkout - v_checkin;
    v_valor := PKG_TURISMOUQ.fn_valor_estadia(v_id_hab, v_checkin, v_checkout);

    DBMS_OUTPUT.PUT_LINE('Habitación ID : ' || v_id_hab);
    DBMS_OUTPUT.PUT_LINE('Fecha Checkin : ' || TO_CHAR(v_checkin, 'YYYY-MM-DD'));
    DBMS_OUTPUT.PUT_LINE('Fecha Checkout: ' || TO_CHAR(v_checkout, 'YYYY-MM-DD'));
    DBMS_OUTPUT.PUT_LINE('Noches totales: ' || v_total_dias || ' noches (4 en Temporada Alta + 4 en Temporada Media)');
    DBMS_OUTPUT.PUT_LINE('Valor calculado por fn_valor_estadia: $' || TO_CHAR(v_valor, '999,999,990.00'));
END;
/

-- Prueba 2: sp_crear_reserva exitosa
-- Caso: Registrar una reserva válida para el cliente 1 en habitación 1 
-- (IDs generados por secuencia)
DECLARE
    v_id_reserva_nueva NUMBER;
BEGIN
    sp_crear_reserva(
        p_id_cliente => 1,
        p_id_habitacion => 1,
        p_fecha_checkin => DATE '2027-01-10',
        p_fecha_checkout => DATE '2027-01-15',
        p_cantidad_huespedes => 2,
        p_id_reserva => v_id_reserva_nueva
    );

    DBMS_OUTPUT.PUT_LINE('Reserva creada correctamente con ID: ' || v_id_reserva_nueva);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Rollback de prueba ejecutado satisfactoriamente.');
END;
/

-- Prueba 3: Validación de excepciones con el procedimiento sp_crear_reserva 
-- usando RAISE_APPLICATION_ERROR

-- Checkout anterior o igual al Checkin (-20002)
DECLARE
    v_id_res NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('Probando Checkout <= Checkin');
    sp_crear_reserva(1, 1, DATE '2027-05-10', DATE '2027-05-08', 2, v_id_res);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Captura esperada: ' || SQLERRM);
END;
/

-- Capacidad máxima excedida (-20003)
DECLARE
    v_id_res NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('Probando Capacidad Excedida (20 personas en una habitación sencilla)');
    sp_crear_reserva(1, 1, DATE '2027-06-01', DATE '2027-06-05', 20, v_id_res);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Captura esperada: ' || SQLERRM);
END;
/

-- Habitación no disponible por fechas solapadas (-20001)
DECLARE
    v_id_res1 NUMBER;
    v_id_res2 NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('Probando Habitación No Disponible (solapamiento directo)');
    
    -- Pedir 1 huésped (la habitación 2 es individual)
    sp_crear_reserva(1, 2, DATE '2027-08-10', DATE '2027-08-20', 1, v_id_res1);
    
    -- Intentar solapar fechas (15 al 25 de agosto) con 1 huésped
    sp_crear_reserva(2, 2, DATE '2027-08-15', DATE '2027-08-25', 1, v_id_res2);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Captura esperada: ' || SQLERRM);
        ROLLBACK;
END;
/

-- Prueba 4: Proceso masivo de liquidación mensual con el cursor explícito 
-- parametrizado sp_liquidacion_mensual
BEGIN
    PKG_TURISMOUQ.sp_liquidacion_mensual(p_anio => 2025, p_mes => 7);
END;
/

-- Prueba 5: Disparador a nivel de sentencia (Auditoría de cambios sobre TARIFA)
DECLARE
    v_conteo_antes   NUMBER;
    v_conteo_despues NUMBER;
    v_precio_orig    NUMBER(12,2);
BEGIN
    SELECT COUNT(*) INTO v_conteo_antes FROM AuditoriaTarifa;
    SELECT precio_noche INTO v_precio_orig FROM Tarifa WHERE id_tarifa = 1;

    UPDATE Tarifa
    SET precio_noche = precio_noche + 15000
    WHERE id_tarifa = 1;

    SELECT COUNT(*) INTO v_conteo_despues FROM AuditoriaTarifa;

    DBMS_OUTPUT.PUT_LINE('Registros en AuditoriaTarifa antes : ' || v_conteo_antes);
    DBMS_OUTPUT.PUT_LINE('Registros en AuditoriaTarifa después: ' || v_conteo_despues);

    FOR r IN (
        SELECT id_auditoria, id_tarifa, precio_anterior, precio_nuevo, operacion, usuario, fecha_cambio
        FROM AuditoriaTarifa
        WHERE id_tarifa = 1
        ORDER BY id_auditoria DESC
        FETCH FIRST 1 ROWS ONLY
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('Última auditoría: Tarifa ' || r.id_tarifa || 
                             ' | Anterior: $' || r.precio_anterior || 
                             ' | Nuevo: $' || r.precio_nuevo || 
                             ' | Operación: ' || r.operacion || 
                             ' | Usuario: ' || r.usuario || 
                             ' | Fecha: ' || TO_CHAR(r.fecha_cambio, 'YYYY-MM-DD HH24:MI:SS'));
    END LOOP;

    UPDATE Tarifa SET precio_noche = v_precio_orig WHERE id_tarifa = 1;
    COMMIT;
END;
/

-- Prueba 6: Disparador compuesto de solape a nivel de fila, con dos inserciones solapadas 
-- antes del COMMIT, así se muestra que se impida el solape en ReservaHabitacion.
-- Pero además se agrega una tercera inserción que empieza el día del checkout anterior
DECLARE
    v_id_res1 NUMBER;
    v_id_res2 NUMBER;
    v_id_res3 NUMBER;
BEGIN
    v_id_res1 := seq_reserva.NEXTVAL;
    v_id_res2 := seq_reserva.NEXTVAL;
    v_id_res3 := seq_reserva.NEXTVAL;
 
    -- Crear las reservas principales
    INSERT INTO Reserva
    VALUES (v_id_res1, 1, SYSDATE, DATE '2028-03-01', DATE '2028-03-10', 'CONFIRMADA');
    
    INSERT INTO Reserva
    VALUES (v_id_res2, 2, SYSDATE, DATE '2028-03-05', DATE '2028-03-15', 'CONFIRMADA');
    
    INSERT INTO Reserva
    VALUES (v_id_res3, 3, SYSDATE, DATE '2028-03-10', DATE '2028-03-12', 'CONFIRMADA');
    
    -- Primera inserción: habitación 5, del 01 al 10 de marzo
    INSERT INTO ReservaHabitacion VALUES (seq_reserva_habitacion.NEXTVAL, v_id_res1, 5, DATE '2028-03-01',
        DATE '2028-03-10', 2);
    DBMS_OUTPUT.PUT_LINE('1) Primera inserción aceptada: 01 al 10 de Marzo.');

    -- Segunda inserción solapada con fecha de 05 al 15 de marzo del 2028, en la 
    -- misma transacción
    BEGIN
        INSERT INTO ReservaHabitacion
        VALUES (seq_reserva_habitacion.NEXTVAL, v_id_res2, 5, DATE '2028-03-05', DATE '2028-03-15', 2);
        DBMS_OUTPUT.PUT_LINE('ERROR: el disparador no bloqueó el solapamiento.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20010 THEN
                DBMS_OUTPUT.PUT_LINE('2) Éxito: el disparador bloqueó el solape.');
                DBMS_OUTPUT.PUT_LINE('   Mensaje: ' || SQLERRM);
            ELSE
                RAISE;
            END IF;
    END;
    
    -- Tercera inserción que empieza el día del checkout anterior, la cual debe
    -- aceptarse porque las fechas son contiguas
    INSERT INTO ReservaHabitacion
    VALUES (seq_reserva_habitacion.NEXTVAL, v_id_res3, 5, DATE '2028-03-10', DATE '2028-03-12', 2);
    DBMS_OUTPUT.PUT_LINE('3) Inserción contigua (checkin = checkout anterior) aceptada.');
 
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Rollback de prueba ejecutado. No quedan datos de la prueba.');

EXCEPTION
    WHEN OTHERS THEN 
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error en la prueba: ' || SQLERRM);
END;
/

-- Prueba 7: Consulta y refresco de la Vista Materializada
BEGIN
    DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');
    DBMS_OUTPUT.PUT_LINE('Vista Materializada mv_ocupacion_mensual refrescada exitosamente.');
END;
/

SELECT 
    anio, 
    mes, 
    nombre_municipio, 
    nombre_alojamiento, 
    total_reservas_completadas, 
    total_noches_ocupadas,
    noches_disponibles,
    porcentaje_ocupacion, 
    TO_CHAR(total_ingresos_hospedaje, '$999,999,990') AS ingresos_hospedaje
FROM mv_ocupacion_mensual
WHERE anio = 2025 AND mes = 7
ORDER BY total_ingresos_hospedaje DESC
FETCH FIRST 5 ROWS ONLY;

-- Prueba 8: Cuadre entre la liquidación y la vista materializada para Julio de 2025
SELECT
    NVL(l.id_alojamiento, v.id_alojamiento) AS id_alojamiento,
    l.total_noches AS noches_liquidacion,
    v.total_noches_ocupadas AS noches_vista,
    l.total_ingresos_estadia AS ingresos_liquidacion,
    v.total_ingresos_hospedaje AS ingresos_vista,
    CASE
        WHEN NVL(l.total_noches, -1) = NVL(v.total_noches_ocupadas, -1)
            AND NVL(l.total_ingresos_estadia, -1) = NVL(v.total_ingresos_hospedaje, -1)
        THEN 'CUADRA' ELSE 'DIFERENCIA'
    END AS resultado
FROM (SELECT * FROM LiquidacionMensual WHERE anio = 2025 AND mes = 7) l
FULL OUTER JOIN (SELECT * FROM mv_ocupacion_mensual WHERE anio = 2025 AND mes = 7) v
    ON l.id_alojamiento = v.id_alojamiento
ORDER BY resultado DESC, id_alojamiento
FETCH FIRST 10 ROWS ONLY;

-- Resumen de la prueba anterior, la columna "diferencias" debe ser 0
SELECT COUNT(*) AS alojamientos_comparados,
       SUM(CASE WHEN NVL(l.total_noches, -1) = NVL(v.total_noches_ocupadas, -1)
                    AND NVL(l.total_ingresos_estadia, -1) = NVL(v.total_ingresos_hospedaje, -1)
                THEN 0 ELSE 1 END) AS diferencias
FROM (SELECT * FROM LiquidacionMensual WHERE anio = 2025 AND mes = 7) l
FULL OUTER JOIN (SELECT * FROM mv_ocupacion_mensual WHERE anio = 2025 AND mes = 7) v
    ON l.id_alojamiento = v.id_alojamiento;

-- Prueba 9: El histórico está en su tablespace
SELECT table_name, tablespace_name
FROM user_tables
WHERE table_name = 'HISTORICORESERVA';

-- Prueba 10: Paso al histórico
DECLARE
    v_antes     NUMBER;
    v_despues   NUMBER;
    v_historico NUMBER;
    v_archivadas NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_antes FROM Reserva;
 
    sp_archivar_reservas(p_fecha_corte => DATE '2024-03-01', p_total_archivadas => v_archivadas);
 
    SELECT COUNT(*) INTO v_despues   FROM Reserva;
    SELECT COUNT(*) INTO v_historico FROM HistoricoReserva;
 
    DBMS_OUTPUT.PUT_LINE('Reservas operativas antes: ' || v_antes);
    DBMS_OUTPUT.PUT_LINE('Reservas archivadas: ' || v_archivadas);
    DBMS_OUTPUT.PUT_LINE('Reservas operativas después: ' || v_despues);
    DBMS_OUTPUT.PUT_LINE('Filas en HistoricoReserva: ' || v_historico);
    
    ROLLBACK;
    
    SELECT COUNT(*) INTO v_despues FROM Reserva;
    DBMS_OUTPUT.PUT_LINE('Tras el ROLLBACK, reservas operativas: ' || v_despues);
END;
/