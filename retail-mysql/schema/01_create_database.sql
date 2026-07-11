-- ============================================================
-- Enterprise Retail Management Database System
-- Script: 01_create_database.sql
-- Purpose: Create the database with proper charset/collation
-- Engine target: MySQL 8.0+
-- ============================================================

DROP DATABASE IF EXISTS retail_enterprise_db;

CREATE DATABASE retail_enterprise_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE retail_enterprise_db;

-- Sane defaults for a session doing bulk DDL/DML
SET GLOBAL local_infile = 1;
SET SESSION sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO';
