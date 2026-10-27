-- Casos de prueba y demostración

-- Prueba 1: Cálculo de estadía usando la función fn_valor_estadia con cruce de 
-- múltiples temporadas
-- Caso: Habitación 1 reservada del 25 de febrero al 05 de marzo de 2025.
-- Atraviesa Temporada Alta 2025 (hasta el 28 de febrero)
-- y Temporada Media 2025 (desde el 01 de marzo). 
DECLARE
    v_id_hab     NUMBER := 1;
    v_checkin    DATE := DATE '2025-02-25';
    v_checkout   DATE := DATE '2025-03-05';
    v_total_dias NUMBER;
    v_valor      NUMBER(12,2);
BEGIN
    v_total_dias := v_checkout - v_checkin;
    v_valor := PKG_TURISMOUQ.fn_valor_estadia(v_id_hab, v_checkin, v_checkout);

    DBMS_OUTPUT.PUT_LINE('Habitación ID : ' || v_id_hab);
    DBMS_OUTPUT.PUT_LINE('Fecha Checkin : ' || TO_CHAR(v_checkin, 'YYYY-MM-DD'));
    DBMS_OUTPUT.PUT_LINE('Fecha Checkout: ' || TO_CHAR(v_checkout, 'YYYY-MM-DD'));
    DBMS_OUTPUT.PUT_LINE('Noches totales: ' || v_total_dias || ' noches (3 en Temporada Alta + 5 en Temporada Media)');
    DBMS_OUTPUT.PUT_LINE('Valor calculado por fn_valor_estadia: $' || TO_CHAR(v_valor, '999,999,990.00'));
END;
/

-- Prueba 2: sp_crear_reserva exitosa
-- Caso: Registrar una reserva válida para el cliente 1 en habitación 1.
DECLARE
    v_id_reserva_nueva NUMBER;
BEGIN
    sp_crear_reserva(
        p_id_cliente         => 1,
        p_id_habitacion      => 1,
        p_fecha_checkin      => DATE '2027-01-10',
        p_fecha_checkout     => DATE '2027-01-15',
        p_cantidad_huespedes => 2,
        p_id_reserva         => v_id_reserva_nueva
    );

    DBMS_OUTPUT.PUT_LINE('Reserva creada correctamente con ID: ' || v_id_reserva_nueva);
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Rollback de prueba ejecutado satisfactoriamente.');
END;
/

-- Prueba 3: Validación de excepciones con el procedimiento sp_crear_reserva 
-- usando RAISE y RAISE_APPLICATION_ERROR

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
    DBMS_OUTPUT.PUT_LINE('Probando Capacidad Excedida (solicitando 20 personas en una habitación sencilla)');
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

-- Prueba 6: Disparador a nivel de fila para impedir solape en ReservaHabitacion
DECLARE
    v_nuevo_id_res NUMBER;
    v_nuevo_id_rh  NUMBER;
BEGIN
    SELECT NVL(MAX(id_reserva), 0) + 9999 INTO v_nuevo_id_res FROM Reserva;
    SELECT NVL(MAX(id_reserva_habitacion), 0) + 9999 INTO v_nuevo_id_rh FROM ReservaHabitacion;

    -- Se inserta y confirma la reserva base
    INSERT INTO Reserva VALUES (v_nuevo_id_res, 1, SYSDATE, DATE '2028-03-01', DATE '2028-03-10', 'CONFIRMADA');
    INSERT INTO ReservaHabitacion VALUES (v_nuevo_id_rh, v_nuevo_id_res, 5, DATE '2028-03-01', DATE '2028-03-10', 2);
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Insertando reserva solapada para probar el disparador de fila');
    
    -- Intento de inserción de reserva solapada (05 al 15 de marzo de 2028 sobre habitación 5)
    INSERT INTO ReservaHabitacion VALUES (v_nuevo_id_rh + 1, v_nuevo_id_res, 5, DATE '2028-03-05', DATE '2028-03-15', 2);
    
    DBMS_OUTPUT.PUT_LINE('ERROR: El disparador no bloqueó el solapamiento.');
    
    -- Limpieza en caso de fallo
    DELETE FROM ReservaHabitacion WHERE id_reserva = v_nuevo_id_res;
    DELETE FROM Reserva WHERE id_reserva = v_nuevo_id_res;
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Éxito: El disparador de fila bloqueó el solape correctamente.');
        DBMS_OUTPUT.PUT_LINE('Mensaje capturado: ' || SQLERRM);
        
        -- Limpieza de la reserva base de prueba
        DELETE FROM ReservaHabitacion WHERE id_reserva = v_nuevo_id_res;
        DELETE FROM Reserva WHERE id_reserva = v_nuevo_id_res;
        COMMIT;
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
    total_huespedes_atendidos, 
    TO_CHAR(total_ingresos_hospedaje, '$999,999,990') AS ingresos_hospedaje
FROM mv_ocupacion_mensual
WHERE anio = 2025 AND mes = 7
ORDER BY total_ingresos_hospedaje DESC
FETCH FIRST 5 ROWS ONLY;