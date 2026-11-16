-- Proyecto Integrador: TurismoUQ - Plataforma de Reservas
-- Asignatura: Bases de Datos II
-- Script 00: Usuario y permisos Grant (Privilegios)
-- Entrega 2 del Proyecto

--------------------------------------------------------------------------------

-- Primero debemos conectarnos a FREEPDB1
ALTER SESSION SET CONTAINER = FREEPDB1;

-- Crear el usuario dueño del esquema "TURISMO"
CREATE USER turismo IDENTIFIED BY turismo
    DEFAULT TABLESPACE users
    TEMPORARY TABLESPACE temp;

-- Ejecutar lo siguiente conectado como un usuario con permisos SYSTEM.  
GRANT CREATE SESSION TO TURISMO;
GRANT CREATE TABLE TO TURISMO;
GRANT CREATE SEQUENCE TO TURISMO;
GRANT CREATE VIEW TO TURISMO;
GRANT CREATE PROCEDURE TO TURISMO;
GRANT CREATE TRIGGER TO TURISMO;
GRANT CREATE MATERIALIZED VIEW TO TURISMO;
GRANT CREATE TABLESPACE TO TURISMO;

-- Permite crear tablas en el tablespace ts_historico_reservas (cuota de espacio)
GRANT UNLIMITED TABLESPACE TO TURISMO;

-- Permite al usuario consultar tablas en transacciones y manejar vistas 
-- materializadas
GRANT QUERY REWRITE TO TURISMO;