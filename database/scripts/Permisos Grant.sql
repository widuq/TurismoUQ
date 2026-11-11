-- PROYECTO INTEGRADOR: TURISMOUQ - PLATAFORMA DE RESERVAS
-- ASIGNATURA: BASES DE DATOS II
-- Script: Permisos Grant (Privilegios)
-- Entrega 2 del Proyecto

-- Primero debemos conectarnos al PDB
ALTER SESSION SET CONTAINER = XEPDB1;

-- Ejecutar lo siguiente conectado como un usuario con permisos SYSTEM.  
GRANT CREATE SESSION TO PROYECTO;
GRANT CREATE TABLE TO PROYECTO;
GRANT CREATE SEQUENCE TO PROYECTO;
GRANT CREATE VIEW TO PROYECTO;
GRANT CREATE PROCEDURE TO PROYECTO;
GRANT CREATE TRIGGER TO PROYECTO;
GRANT CREATE MATERIALIZED VIEW TO PROYECTO;
GRANT CREATE TABLESPACE TO PROYECTO;

-- Permite crear tablas en el tablespace ts_historico_reservas (cuota de espacio)
GRANT UNLIMITED TABLESPACE TO PROYECTO;

-- Permite al usuario consultar tablas en transacciones y manejar vistas 
-- materializadas
GRANT QUERY REWRITE TO PROYECTO;
 
