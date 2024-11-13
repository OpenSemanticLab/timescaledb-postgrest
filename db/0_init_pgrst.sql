-- 0_init_pgrst.sql

-- Authors: 
  -- Andreas Räder, https://github.com/raederan 

-- Initialize schema for TimescaleDB as PostgREST endpoints 
CREATE SCHEMA api;
SET search_path TO api;

-- Revoking default privileges to prevent public access to functions
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
CREATE EXTENSION timescaledb;

-- Create user roles
CREATE ROLE api_user nologin;
CREATE ROLE api_anon nologin;

-- !TODO: replace line using Ansible regex to set password from inventory
CREATE ROLE authenticator WITH NOINHERIT LOGIN PASSWORD 'MY_SECRET_PASSWORD';

-- Set permissions
GRANT api_anon TO authenticator;
GRANT api_user TO authenticator;
GRANT USAGE ON SCHEMA api TO api_anon;
GRANT ALL ON SCHEMA api TO api_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA api TO api_user;

-- create event trigger function (automatic schema cache reloading)
CREATE OR REPLACE FUNCTION api.pgrst_watch() 
RETURNS event_trigger
LANGUAGE plpgsql
AS $$
BEGIN
NOTIFY pgrst, 'reload schema';
END;
$$;

-- create event trigger procedure for every ddl_command_end event
CREATE EVENT TRIGGER pgrst_watch ON ddl_command_end
EXECUTE PROCEDURE api.pgrst_watch();

-- Reset default privileges 
ALTER DEFAULT PRIVILEGES GRANT EXECUTE ON FUNCTIONS TO PUBLIC;
