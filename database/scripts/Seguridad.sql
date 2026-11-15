-- PROYECTO INTEGRADOR: TURISMOUQ - PLATAFORMA DE RESERVAS
-- ASIGNATURA: BASES DE DATOS II
-- Script: Seguridad con roles, usuarios, GRANT, vistas y perfil
-- Entrega 3 del Proyecto

--------------------------------------------------------------------------------

-- Ejecutar conectado como SYSTEM

-- Vistas para recepción
-- Recepción no tendrá acceso a las tablas, solo a estas vistas que muestran 
-- únicamente las columnas necesarias para atender, sin montos de pagos.

-- Habitaciones con su alojamiento y municipio
CREATE OR REPLACE VIEW proyecto.vw_recepcion_habitaciones AS
SELECT h.id_habitacion,
       h.numero,
       h.tipo,
       h.capacidad_maxima,
       a.id_alojamiento,
       a.nombre AS alojamiento,
       m.nombre AS municipio
FROM proyecto.Habitacion h
JOIN proyecto.Alojamiento a ON h.id_alojamiento = a.id_alojamiento
JOIN proyecto.Municipio m ON a.id_municipio = m.id_municipio;

-- Clientes con sus datos de contacto
CREATE OR REPLACE VIEW proyecto.vw_recepcion_clientes AS
SELECT id_cliente,
       nombre_completo,
       tipo_documento,
       numero_documento,
       telefono,
       ciudad_origen
FROM proyecto.Cliente;

-- Reservas con cliente, habitación y estado de pago sin mostrar montos
CREATE OR REPLACE VIEW proyecto.vw_recepcion_reservas AS
SELECT r.id_reserva,
       r.estado,
       rh.fecha_checkin,
       rh.fecha_checkout,
       rh.cantidad_huespedes,
       c.id_cliente,
       c.nombre_completo AS cliente,
       h.id_habitacion,
       h.numero AS numero_habitacion,
       a.nombre AS alojamiento,
       CASE
           WHEN EXISTS (SELECT 1 FROM proyecto.Pago p
                WHERE p.id_reserva = r.id_reserva AND p.estado = 'EXITOSO')
           THEN 'CON PAGO'
           ELSE 'SIN PAGO'
       END AS estado_pago
FROM proyecto.Reserva r
JOIN proyecto.ReservaHabitacion rh ON r.id_reserva = rh.id_reserva
JOIN proyecto.Cliente c ON r.id_cliente = c.id_cliente
JOIN proyecto.Habitacion h ON rh.id_habitacion = h.id_habitacion
JOIN proyecto.Alojamiento a ON h.id_alojamiento = a.id_alojamiento;

-- Perfil con límites de sesión
CREATE PROFILE perfil_turismouq LIMIT
    -- Máximo 2 sesiones simultáneas por usuario
    SESSIONS_PER_USER 2         
    -- Una sesión dura máximo 8 horas 
    CONNECT_TIME 480            
    -- La sesión se cierra tras 15 minutos sin actividad
    IDLE_TIME 15 
    -- 3 contraseñas erróneas bloquean la cuenta durante una hora
    FAILED_LOGIN_ATTEMPTS 3     
    PASSWORD_LOCK_TIME 1/24;    

-- Roles
CREATE ROLE rol_recepcion;
CREATE ROLE rol_admin_alojamiento;
CREATE ROLE rol_gerente;
CREATE ROLE rol_auditor;

GRANT CREATE SESSION TO rol_recepcion;
GRANT CREATE SESSION TO rol_admin_alojamiento;
GRANT CREATE SESSION TO rol_gerente;
GRANT CREATE SESSION TO rol_auditor;

-- Privilegios de recepción: solo vistas y procedimientos, ninguna tabla
GRANT SELECT ON proyecto.vw_recepcion_habitaciones TO rol_recepcion;
GRANT SELECT ON proyecto.vw_recepcion_clientes TO rol_recepcion;
GRANT SELECT ON proyecto.vw_recepcion_reservas TO rol_recepcion;
GRANT EXECUTE ON proyecto.sp_crear_reserva_segura TO rol_recepcion;
GRANT EXECUTE ON proyecto.sp_registrar_reserva_pago TO rol_recepcion;

-- Privilegios del administrador de alojamiento: gestiona habitaciones, 
-- tarifas y servicios, consulta reservas y pagos, solo puede cambiar el estado
-- de una reserva
GRANT SELECT, INSERT, UPDATE ON proyecto.Habitacion TO rol_admin_alojamiento;
GRANT SELECT, INSERT, UPDATE ON proyecto.Tarifa TO rol_admin_alojamiento;
GRANT SELECT, INSERT, UPDATE ON proyecto.Servicio TO rol_admin_alojamiento;
GRANT SELECT ON proyecto.Municipio TO rol_admin_alojamiento;
GRANT SELECT ON proyecto.TipoAlojamiento TO rol_admin_alojamiento;
GRANT SELECT ON proyecto.Alojamiento TO rol_admin_alojamiento;
GRANT SELECT ON proyecto.Temporada TO rol_admin_alojamiento;
GRANT SELECT ON proyecto.Cliente TO rol_admin_alojamiento;
GRANT SELECT ON proyecto.Reserva TO rol_admin_alojamiento;
GRANT SELECT ON proyecto.ReservaHabitacion TO rol_admin_alojamiento;
GRANT SELECT ON proyecto.ReservaServicio TO rol_admin_alojamiento;
GRANT SELECT ON proyecto.Pago TO rol_admin_alojamiento;
GRANT SELECT ON proyecto.Resena TO rol_admin_alojamiento;
GRANT UPDATE (estado) ON proyecto.Reserva TO rol_admin_alojamiento;
GRANT EXECUTE ON proyecto.sp_crear_reserva_segura TO rol_admin_alojamiento;
GRANT EXECUTE ON proyecto.sp_registrar_reserva_pago TO rol_admin_alojamiento;

-- Privilegios del gerente: consulta la operación y los reportes, y puede 
-- ejecutar la liquidación mensual
GRANT SELECT ON proyecto.Municipio TO rol_gerente;
GRANT SELECT ON proyecto.TipoAlojamiento TO rol_gerente;
GRANT SELECT ON proyecto.Alojamiento TO rol_gerente;
GRANT SELECT ON proyecto.Habitacion TO rol_gerente;
GRANT SELECT ON proyecto.Temporada TO rol_gerente;
GRANT SELECT ON proyecto.Tarifa TO rol_gerente;
GRANT SELECT ON proyecto.Cliente TO rol_gerente;
GRANT SELECT ON proyecto.Reserva TO rol_gerente;
GRANT SELECT ON proyecto.ReservaHabitacion TO rol_gerente;
GRANT SELECT ON proyecto.Servicio TO rol_gerente;
GRANT SELECT ON proyecto.ReservaServicio TO rol_gerente;
GRANT SELECT ON proyecto.Pago TO rol_gerente;
GRANT SELECT ON proyecto.Resena TO rol_gerente;
GRANT SELECT ON proyecto.LiquidacionMensual TO rol_gerente;
GRANT SELECT ON proyecto.HistoricoReserva TO rol_gerente;
GRANT SELECT ON proyecto.mv_ocupacion_mensual TO rol_gerente;
GRANT EXECUTE ON proyecto.sp_liquidacion_mensual TO rol_gerente;

-- Privilegios del auditor: solo lectura de lo necesario
GRANT SELECT ON proyecto.AuditoriaTarifa TO rol_auditor;
GRANT SELECT ON proyecto.Tarifa TO rol_auditor;
GRANT SELECT ON proyecto.Pago TO rol_auditor;
GRANT SELECT ON proyecto.Reserva TO rol_auditor;
GRANT SELECT ON proyecto.ReservaHabitacion TO rol_auditor;
GRANT SELECT ON proyecto.LiquidacionMensual TO rol_auditor;
GRANT SELECT ON proyecto.HistoricoReserva TO rol_auditor;

-- Usuarios, uno por cada rol, con el perfil de límites de sesión
-- ninguno puede ver la tabla UsuarioSistema, porque contiene contraseñas.
CREATE USER usr_recepcion IDENTIFIED BY "Recepcion#2026" PROFILE perfil_turismouq;
CREATE USER usr_admin_aloj IDENTIFIED BY "AdminAloj#2026" PROFILE perfil_turismouq;
CREATE USER usr_gerente IDENTIFIED BY "Gerente#2026" PROFILE perfil_turismouq;
CREATE USER usr_auditor IDENTIFIED BY "Auditor#2026" PROFILE perfil_turismouq;

GRANT rol_recepcion TO usr_recepcion;
GRANT rol_admin_alojamiento TO usr_admin_aloj;
GRANT rol_gerente TO usr_gerente;
GRANT rol_auditor TO usr_auditor;

-- Verificación de usuarios, perfil y roles
SELECT username, profile, account_status
FROM dba_users
WHERE username IN ('USR_RECEPCION', 'USR_ADMIN_ALOJ', 'USR_GERENTE', 'USR_AUDITOR')
ORDER BY username;

SELECT grantee, granted_role
FROM dba_role_privs
WHERE grantee IN ('USR_RECEPCION', 'USR_ADMIN_ALOJ', 'USR_GERENTE', 'USR_AUDITOR')
ORDER BY grantee;

SELECT resource_name, limit
FROM dba_profiles
WHERE profile = 'PERFIL_TURISMOUQ'
    AND resource_name IN ('SESSIONS_PER_USER', 'CONNECT_TIME', 'IDLE_TIME', 
        'FAILED_LOGIN_ATTEMPTS', 'PASSWORD_LOCK_TIME');