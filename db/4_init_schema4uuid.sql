-- 4_init_schema4uuid.sql

-- Authors: 
  -- Andreas Räder, https://github.com/raederan

SET search_path TO api;

-- Internal schema channels
CREATE TABLE IF NOT EXISTS api.channels (
  osw_channel UUID PRIMARY KEY,
  osw_tool UUID NOT NULL
);
-- GRANT SELECT on api.channels to api_anon;
GRANT ALL on api.channels to api_user;

-- Internal schema channeldata
CREATE TABLE IF NOT EXISTS api.channeldata (
  osw_channel UUID NOT NULL,
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

-- Create synthetic data for query testing
-- Function to generate synthetic data into channeldata, input is channel id and number of data points
DROP FUNCTION IF EXISTS api.gen_data;
CREATE OR REPLACE FUNCTION api.gen_data(channel UUID, datapoints INT, days_offset INT DEFAULT 0, tool UUID DEFAULT NULL)
-- Return message if channel and tool do not exist
RETURNS TEXT AS $$
DECLARE
  create_msg TEXT;
  insert_msg TEXT;
  _tool UUID;

BEGIN
  create_msg := '';
  insert_msg := '';
  -- Check if tool is provided, if not use tool from channel
  IF tool IS NOT NULL THEN
    _tool := tool;
  ELSE
    _tool := (SELECT osw_tool FROM api.channels WHERE osw_channel = channel);
  END IF;

  -- Raise Error if tool is not provided and not found in channel
  IF _tool IS NULL THEN
    RAISE EXCEPTION 'The provided channel is not associated with a tool, either use an existing channel or provide a tool id to be created!';
  END IF;

  -- Raise Error if channel exists and tool does not match
  IF EXISTS (SELECT * FROM api.channels WHERE osw_channel = channel AND osw_tool <> _tool) THEN
    RAISE EXCEPTION 'Channel exists but tool does not match!';
  END IF;

  -- Create channel if not exists but tool exists
  IF EXISTS (SELECT 1 FROM api.channels WHERE osw_channel <> channel AND osw_tool = _tool) THEN
    -- Case 1 Channel does not exist at all and tool exists -> create channel with tool
    IF NOT EXISTS (SELECT 1 FROM api.channels WHERE osw_channel = channel) THEN
      INSERT INTO api.channels (osw_channel, osw_tool) VALUES (channel, _tool);
      -- message that channel and tool were created
      RAISE NOTICE 'Channel for existing Tool created successfully!'; 
      create_msg := 'Channel for existing Tool and ';
    END IF;
  END IF;

  -- Create channel and tool if both do not exist
  IF NOT EXISTS (SELECT 1 FROM api.channels WHERE osw_channel = channel AND osw_tool = _tool) THEN
    INSERT INTO api.channels (osw_channel, osw_tool) VALUES (channel, _tool);
    -- message that channel and tool were created
    RAISE NOTICE 'Channel and Tool created successfully!'; 
    create_msg := 'Channel, Tool and ';
  END IF;
  
  INSERT INTO api.channeldata(osw_channel, ts, data)
  SELECT
    channel,
    '2024-01-01T00:00:00.000000+00'::TIMESTAMPTZ + (days_offset * interval '1 day') + (generate_series(1, datapoints) ) * interval '1 microseconds',
    ('{"value":'||(random()*100)::real||'}')::json;
  -- message that data was created
  RAISE NOTICE 'Data generated successfully!';
  insert_msg := 'Data generated successfully!';

  RETURN create_msg || insert_msg;
END;
$$ LANGUAGE plpgsql
SET statement_timeout TO '300s';

-- -- Overloaded function without 'days_offset' variable (NOT REQUIRED FOR API, CAUSE JSON REFERENCES INTEGRITY)
-- CREATE OR REPLACE FUNCTION api.gen_data(channel UUID, datapoints INT, tool UUID DEFAULT NULL)
-- -- Return message if channel and tool do not exist
-- RETURNS TEXT AS $$
-- DECLARE
--   create_msg TEXT;
--   insert_msg TEXT;
--   _tool UUID;

-- BEGIN
--   create_msg := '';
--   insert_msg := '';
--   -- Check if tool is provided, if not use tool from channel
--   IF tool IS NOT NULL THEN
--     _tool := tool;
--   ELSE
--     _tool := (SELECT osw_tool FROM api.channels WHERE osw_channel = channel);
--   END IF;

--   -- Raise Error if tool is not provided and not found in channel
--   IF _tool IS NULL THEN
--     RAISE EXCEPTION 'The provided channel is not associated with a tool, either use an existing channel or provide a tool id to be created!';
--   END IF;

--   -- Raise Error if channel exists and tool does not match
--   IF EXISTS (SELECT * FROM api.channels WHERE osw_channel = channel AND osw_tool <> _tool) THEN
--     RAISE EXCEPTION 'Channel exists but tool does not match!';
--   END IF;

--   -- Create channel if not exists but tool exists
--   IF EXISTS (SELECT 1 FROM api.channels WHERE osw_channel <> channel AND osw_tool = _tool) THEN
--     -- Case 1 Channel does not exist at all and tool exists -> create channel with tool
--     IF NOT EXISTS (SELECT 1 FROM api.channels WHERE osw_channel = channel) THEN
--       INSERT INTO api.channels (osw_channel, osw_tool) VALUES (channel, _tool);
--       -- message that channel and tool were created
--       RAISE NOTICE 'Channel for existing Tool created successfully!'; 
--       create_msg := 'Channel for existing Tool and ';
--     END IF;
--   END IF;

--   -- Create channel and tool if both do not exist
--   IF NOT EXISTS (SELECT 1 FROM api.channels WHERE osw_channel = channel AND osw_tool = _tool) THEN
--     INSERT INTO api.channels (osw_channel, osw_tool) VALUES (channel, _tool);
--     -- message that channel and tool were created
--     RAISE NOTICE 'Channel and Tool created successfully!'; 
--     create_msg := 'Channel, Tool and ';
--   END IF;
  
--   INSERT INTO api.channeldata(osw_channel, ts, data)
--   SELECT
--     channel,
--     '2024-01-01T00:00:00.000000+00'::TIMESTAMPTZ + (generate_series(1, datapoints) ) * interval '1 microseconds',
--     ('{"value":'||(random()*100)::real||'}')::json;
--   -- message that data was created
--   RAISE NOTICE 'Data generated successfully!';
--   insert_msg := 'Data generated successfully!';

--   RETURN create_msg || insert_msg;
-- END;
-- $$ LANGUAGE plpgsql;

-- -- FUNCTION TESTS 'api.gen_data'
-- -- Create data for 10 channels on 10 tools
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0001', 2, 0, '24f9c902-423f-4733-a96c-c26sctest0t0001');
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0002', 2, 1, '24f9c902-423f-4733-a96c-c26sctest0t0002');
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0003', 2, 2, '24f9c902-423f-4733-a96c-c26sctest0t0003');
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0004', 2, 3, '24f9c902-423f-4733-a96c-c26sctest0t0004');
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0005', 2, 4, '24f9c902-423f-4733-a96c-c26sctest0t0005');
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0006', 2, 5, '24f9c902-423f-4733-a96c-c26sctest0t0006');
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0007', 2, 6, '24f9c902-423f-4733-a96c-c26sctest0t0007');
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0008', 2, 7, '24f9c902-423f-4733-a96c-c26sctest0t0008');
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0009', 2, 8, '24f9c902-423f-4733-a96c-c26sctest0t0009');
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0010', 2, 9, '24f9c902-423f-4733-a96c-c26sctest0t0010');

-- -- Create data for 10 channels on 10 tools (WORKS ONLY, WHEN FUNCTION IS OVERLOADED)
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0001', 2, '24f9c902-423f-4733-a96c-c26sctest0t0001');
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0002', 2, '24f9c902-423f-4733-a96c-c26sctest0t0002');
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0003', 2, '24f9c902-423f-4733-a96c-c26sctest0t0003');
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0004', 2, '24f9c902-423f-4733-a96c-c26sctest0t0004');
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0005', 2, '24f9c902-423f-4733-a96c-c26sctest0t0005');
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0006', 2, '24f9c902-423f-4733-a96c-c26sctest0t0006');
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0007', 2, '24f9c902-423f-4733-a96c-c26sctest0t0007');
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0008', 2, '24f9c902-423f-4733-a96c-c26sctest0t0008');
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0009', 2, '24f9c902-423f-4733-a96c-c26sctest0t0009');
-- SELECT api.gen_data('24f9c902-423f-4733-a96c-c26sctest0c0010', 2, '24f9c902-423f-4733-a96c-c26sctest0t0010');