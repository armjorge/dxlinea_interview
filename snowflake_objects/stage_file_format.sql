-- 1. Create the database and schema
CREATE DATABASE IF NOT EXISTS dxlinea_interview;
CREATE SCHEMA IF NOT EXISTS dxlinea_interview.raw_dxlinea;


CREATE SCHEMA IF NOT EXISTS dxlinea_interview.wrk_dxlinea;
CREATE SCHEMA IF NOT EXISTS dxlinea_interview.pub_dxlinea;

-- 2. Switch to the new database and schema context
USE DATABASE dxlinea_interview;
USE SCHEMA raw_dxlinea;

-- 3. Create a named internal stage for uploading your parquet files
CREATE STAGE IF NOT EXISTS raw_dxlinea_stage;

-- 4. Create a file format tailored for Parquet
CREATE FILE FORMAT IF NOT EXISTS dxlinea_ff
    TYPE = PARQUET;
