role = 'DBT_ROLE'
warehouse = 'COMPUTE_WH'
granted_users = {'schema': ['dxlinea_interview.raw_dxlinea', 'dxlinea_interview.wrk_dxlinea', 'dxlinea_interview.pub_dxlinea']}


for schema in granted_users['schema']: 
    grants_message = f""" 
-- Schema ussage {schema}
GRANT USAGE ON SCHEMA {schema} TO ROLE {role};
-- Allow the role to read CURRENT tables/views
GRANT SELECT ON ALL TABLES IN SCHEMA {schema} TO ROLE {role};
GRANT SELECT ON ALL VIEWS IN SCHEMA {schema} TO ROLE {role}; 
-- Create new tables at {schema}
GRANT CREATE TABLE ON SCHEMA {schema} TO ROLE {role};
GRANT CREATE VIEW ON SCHEMA {schema} TO ROLE {role};
GRANT CREATE STAGE ON SCHEMA {schema} TO ROLE {role};
-- select any future table at {schema}
GRANT SELECT ON FUTURE TABLES IN SCHEMA {schema} TO ROLE {role};
GRANT SELECT ON FUTURE VIEWS IN SCHEMA {schema} TO ROLE {role};
    """
    print(grants_message)

warehouse_grants = f'GRANT USAGE ON WAREHOUSE {warehouse} TO ROLE {role};'
print(warehouse_grants)