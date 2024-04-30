-- 4_init_schema4.sql

-- Authors: 
  -- Andreas Räder, https://github.com/raederan

SET search_path TO api;

-- Internal schema channels
CREATE TABLE IF NOT EXISTS api.channels (
  osw_channel CHAR(35) PRIMARY KEY,
  osw_tool CHAR(35) NOT NULL
);
-- GRANT SELECT on api.channels to api_anon;
GRANT ALL on api.channels to api_user;

-- Internal schema channeldata
CREATE TABLE IF NOT EXISTS api.channeldata (
  osw_channel CHAR(35) NOT NULL,
  ts TIMESTAMPTZ NOT NULL,
  data JSONB,
  FOREIGN KEY (osw_channel) REFERENCES api.channels (osw_channel)
);
SELECT api.create_hypertable('api.channeldata', 'ts');
-- GRANT SELECT on api.channeldata to api_anon;
GRANT ALL on api.channeldata to api_user;

-- Create view on channels
DROP VIEW IF EXISTS api.view_channels;
CREATE OR REPLACE VIEW api.view_channels AS
SELECT * FROM api.channels;
GRANT SELECT on api.view_channels to api_anon;
GRANT ALL on api.view_channels to api_user;

-- Create view on channeldata
DROP VIEW IF EXISTS api.view_channeldata;
CREATE OR REPLACE VIEW api.view_channeldata AS
SELECT * FROM api.channeldata;
GRANT SELECT on api.view_channeldata to api_anon;
GRANT ALL on api.view_channeldata to api_user;

-- Create view on channels and channeldata
CREATE VIEW api.view_tooldata AS
SELECT 
  c.osw_channel,
  c.osw_tool,
  cd.ts,
  cd.data
FROM api.channels c
JOIN api.channeldata cd
ON c.osw_channel = cd.osw_channel;
GRANT SELECT on api.view_tooldata to api_anon;
GRANT ALL on api.view_tooldata to api_user;
