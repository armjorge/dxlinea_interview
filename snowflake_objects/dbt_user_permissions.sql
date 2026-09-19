GRANT USAGE ON DATABASE DXLINEA_INTERVIEW TO ROLE DBT_ROLE;

GRANT CREATE SCHEMA ON DATABASE DXLINEA_INTERVIEW TO ROLE DBT_ROLE;

-- Schema ussage dxlinea_interview.raw_dxlinea
GRANT USAGE ON SCHEMA dxlinea_interview.raw_dxlinea TO ROLE DBT_ROLE;
-- Allow the role to read CURRENT tables/views
GRANT SELECT ON ALL TABLES IN SCHEMA dxlinea_interview.raw_dxlinea TO ROLE DBT_ROLE;
GRANT SELECT ON ALL VIEWS IN SCHEMA dxlinea_interview.raw_dxlinea TO ROLE DBT_ROLE; 
-- Create new tables at dxlinea_interview.raw_dxlinea
GRANT CREATE TABLE ON SCHEMA dxlinea_interview.raw_dxlinea TO ROLE DBT_ROLE;
GRANT CREATE VIEW ON SCHEMA dxlinea_interview.raw_dxlinea TO ROLE DBT_ROLE;
GRANT CREATE STAGE ON SCHEMA dxlinea_interview.raw_dxlinea TO ROLE DBT_ROLE;
-- select any future table at dxlinea_interview.raw_dxlinea
GRANT SELECT ON FUTURE TABLES IN SCHEMA dxlinea_interview.raw_dxlinea TO ROLE DBT_ROLE;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA dxlinea_interview.raw_dxlinea TO ROLE DBT_ROLE;
    
 
-- Schema ussage dxlinea_interview.wrk_dxlinea
GRANT USAGE ON SCHEMA dxlinea_interview.wrk_dxlinea TO ROLE DBT_ROLE;
-- Allow the role to read CURRENT tables/views
GRANT SELECT ON ALL TABLES IN SCHEMA dxlinea_interview.wrk_dxlinea TO ROLE DBT_ROLE;
GRANT SELECT ON ALL VIEWS IN SCHEMA dxlinea_interview.wrk_dxlinea TO ROLE DBT_ROLE; 
-- Create new tables at dxlinea_interview.wrk_dxlinea
GRANT CREATE TABLE ON SCHEMA dxlinea_interview.wrk_dxlinea TO ROLE DBT_ROLE;
GRANT CREATE VIEW ON SCHEMA dxlinea_interview.wrk_dxlinea TO ROLE DBT_ROLE;
GRANT CREATE STAGE ON SCHEMA dxlinea_interview.wrk_dxlinea TO ROLE DBT_ROLE;
-- select any future table at dxlinea_interview.wrk_dxlinea
GRANT SELECT ON FUTURE TABLES IN SCHEMA dxlinea_interview.wrk_dxlinea TO ROLE DBT_ROLE;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA dxlinea_interview.wrk_dxlinea TO ROLE DBT_ROLE;
    
 
-- Schema ussage dxlinea_interview.pub_dxlinea
GRANT USAGE ON SCHEMA dxlinea_interview.pub_dxlinea TO ROLE DBT_ROLE;
-- Allow the role to read CURRENT tables/views
GRANT SELECT ON ALL TABLES IN SCHEMA dxlinea_interview.pub_dxlinea TO ROLE DBT_ROLE;
GRANT SELECT ON ALL VIEWS IN SCHEMA dxlinea_interview.pub_dxlinea TO ROLE DBT_ROLE; 
-- Create new tables at dxlinea_interview.pub_dxlinea
GRANT CREATE TABLE ON SCHEMA dxlinea_interview.pub_dxlinea TO ROLE DBT_ROLE;
GRANT CREATE VIEW ON SCHEMA dxlinea_interview.pub_dxlinea TO ROLE DBT_ROLE;
GRANT CREATE STAGE ON SCHEMA dxlinea_interview.pub_dxlinea TO ROLE DBT_ROLE;
-- select any future table at dxlinea_interview.pub_dxlinea
GRANT SELECT ON FUTURE TABLES IN SCHEMA dxlinea_interview.pub_dxlinea TO ROLE DBT_ROLE;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA dxlinea_interview.pub_dxlinea TO ROLE DBT_ROLE;
    
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE DBT_ROLE;