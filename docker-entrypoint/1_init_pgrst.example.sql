-- 1_init_pgrst.sql

-- Authors: 
  -- Andreas Räder, https://github.com/raederan 

-- Initialize schema for TimescaleDB as PostgREST endpoints 
CREATE SCHEMA api;

-- Create user roles
CREATE ROLE api_user nologin;
CREATE ROLE api_anon nologin;

-- !TODO: replace line using Ansible regex to set password from inventory
CREATE ROLE authenticator WITH NOINHERIT LOGIN PASSWORD 'pgrstauth';

-- Set permissions
GRANT api_user TO authenticator;
GRANT api_anon TO authenticator;
GRANT USAGE ON SCHEMA api TO api_anon;
GRANT ALL ON SCHEMA api TO api_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA api TO api_user;
