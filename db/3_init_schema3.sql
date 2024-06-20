-- 3_init_schema3.sql

-- Authors: 
  -- Andreas Räder, https://github.com/raederan

SET search_path TO api;

-- Internal (GET -> View, POST -> RPC)
CREATE TABLE IF NOT EXISTS api.tools (
  osw_tool CHAR(35) PRIMARY KEY
);

-- Internal (GET -> View, POST -> RPC)
CREATE TABLE IF NOT EXISTS api.channels (
  osw_channel CHAR(35) PRIMARY KEY,
  osw_tool CHAR(35) NOT NULL,
  FOREIGN KEY (osw_tool) REFERENCES api.tools (osw_tool)
);

--------- ONLY FOR TESTING, REMOVE IN PRODUCTION ---------
GRANT SELECT on api.tools to api_anon;
GRANT ALL on api.tools to api_user;
GRANT SELECT on api.channels to api_anon;
GRANT ALL on api.channels to api_user;
----------------------------------------------------------

-- Endpoint to create a new data channel endpoint
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
DROP FUNCTION IF EXISTS api.create_channel_endpoint(osw_channel CHAR(35));
CREATE OR REPLACE FUNCTION api.create_channel_endpoint(osw_channel CHAR(35)) RETURNS void AS
$$
BEGIN
    EXECUTE format('CREATE TABLE IF NOT EXISTS api.%I (ts TIMESTAMPTZ NOT NULL, data JSONB)', osw_channel);
    EXECUTE format('SELECT api.create_hypertable(''api.%I'', ''ts'')', osw_channel);
    EXECUTE format('GRANT SELECT on api.%I to api_anon', osw_channel);
    EXECUTE format('GRANT ALL on api.%I to api_user', osw_channel);
END;
$$
LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION api.create_channel_endpoint TO api_user;
ALTER DEFAULT PRIVILEGES GRANT EXECUTE ON FUNCTIONS TO PUBLIC;
GRANT EXECUTE ON FUNCTION api.create_hypertable (regclass, _timescaledb_internal.dimension_info, boolean , boolean, boolean) TO api_user;
GRANT EXECUTE ON FUNCTION api.create_hypertable (regclass, name, name, integer, name, name, anyelement, boolean, boolean, regproc, boolean, text, regproc, regproc) TO api_user;
GRANT EXECUTE ON FUNCTION _timescaledb_functions.insert_blocker() TO api_user;

-- Function to create a tool, returns status message
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
DROP FUNCTION IF EXISTS api.create_tool(osw_tool CHAR(35));
CREATE OR REPLACE FUNCTION api.create_tool(osw_tool CHAR(35)) RETURNS TEXT AS
$$
BEGIN
    INSERT INTO api.tools (osw_tool) VALUES (osw_tool);
    RETURN 'OSW tool created successfully: ' || osw_tool;
END;
$$
LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION api.create_tool(char) TO api_anon;
GRANT EXECUTE ON FUNCTION api.create_tool(char) TO api_user;
ALTER DEFAULT PRIVILEGES GRANT EXECUTE ON FUNCTIONS TO PUBLIC;

-- Overloaded function to create a tool and a channel, returns status message
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
DROP FUNCTION IF EXISTS api.create_tool(osw_tool CHAR(35), osw_channel CHAR(35));
CREATE OR REPLACE FUNCTION api.create_tool(osw_tool CHAR(35), osw_channel CHAR(35)) RETURNS TEXT AS
$$
BEGIN
    INSERT INTO api.tools (osw_tool) VALUES (osw_tool);
    INSERT INTO api.channels (osw_channel, osw_tool) VALUES (osw_channel, osw_tool);
    PERFORM api.create_channel_endpoint(osw_channel);
    RETURN 'OSW tool and channel created successfully';    
END;
$$
LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION api.create_tool(char, char) TO api_anon;
GRANT EXECUTE ON FUNCTION api.create_tool(char, char) TO api_user;
ALTER DEFAULT PRIVILEGES GRANT EXECUTE ON FUNCTIONS TO PUBLIC;

-- Overloaded function to create a tool and multiple channels, returns status message
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
DROP FUNCTION IF EXISTS api.create_tool(osw_tool CHAR(35), osw_channels CHAR(35)[]);
CREATE OR REPLACE FUNCTION api.create_tool(osw_tool CHAR(35), osw_channels CHAR(35)[]) RETURNS TEXT AS
$$
DECLARE
    osw_channel CHAR(35);
BEGIN
    INSERT INTO api.tools (osw_tool) VALUES (osw_tool);
    FOREACH osw_channel IN ARRAY osw_channels
    LOOP
        INSERT INTO api.channels (osw_channel, osw_tool) VALUES (osw_channel, osw_tool);
        PERFORM api.create_channel_endpoint(osw_channel);
    END LOOP;
    RETURN 'OSW tool and channels created successfully';
END;
$$
LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION api.create_tool(char, char[]) TO api_anon;
GRANT EXECUTE ON FUNCTION api.create_tool(char, char[]) TO api_user;
ALTER DEFAULT PRIVILEGES GRANT EXECUTE ON FUNCTIONS TO PUBLIC;

-- Create a channel for a tool
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
DROP FUNCTION IF EXISTS api.create_channel(osw_tool CHAR(35), osw_channel CHAR(35));
CREATE OR REPLACE FUNCTION api.create_channel(osw_tool CHAR(35), osw_channel CHAR(35)) RETURNS TEXT AS
$$
BEGIN
    INSERT INTO api.channels (osw_channel, osw_tool) VALUES (osw_channel, osw_tool);
    PERFORM api.create_channel_endpoint(osw_channel);
    RETURN 'OSW channel created successfully: ' || osw_channel;
END;
$$
LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION api.create_channel TO api_anon;
GRANT EXECUTE ON FUNCTION api.create_channel TO api_user;
ALTER DEFAULT PRIVILEGES GRANT EXECUTE ON FUNCTIONS TO PUBLIC;

-- View to list all channels with their respective tools
DROP VIEW IF EXISTS api.channels_view;
CREATE OR REPLACE VIEW api.channels_view AS
SELECT osw_tool, json_agg(osw_channel) AS osw_channels
FROM api.channels
GROUP BY osw_tool;
GRANT SELECT on api.channels_view to api_anon;
GRANT SELECT on api.channels_view to api_user;

-- View to list all tools
DROP VIEW IF EXISTS api.tools_view;
CREATE OR REPLACE VIEW api.tools_view AS
SELECT osw_tool
FROM api.tools;
GRANT SELECT on api.tools_view to api_anon;
GRANT SELECT on api.tools_view to api_user;

-- function to collect data from multiple channels
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
DROP FUNCTION IF EXISTS api.get_tooldata(osw_tool CHAR(35));
CREATE OR REPLACE FUNCTION api.get_tooldata(osw_tool CHAR(35)) RETURNS TABLE (osw_channel CHAR(35), ts TIMESTAMPTZ, data JSONB) AS
$$
DECLARE
  channels CHAR(35)[]; -- array of channel names
  table_name text;
BEGIN
  -- check if tool exists, return message 'OSW tool not found' if not and exit
  PERFORM * FROM api.tools AS t1 WHERE t1.osw_tool = $1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'OSW tool not found';
  END IF;
  -- get all channels for the tool
  SELECT array_agg(t2.osw_channel) INTO channels FROM api.channels AS t2 WHERE t2.osw_tool = $1;
  FOR i IN 1..array_length(channels, 1)
  LOOP
    table_name := channels[i];
    RETURN QUERY EXECUTE format('SELECT %L::CHAR(35) AS osw_channel, ts, data FROM api.%I', table_name, table_name);
  END LOOP;
END;
$$
LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION api.get_tooldata TO api_anon;
GRANT EXECUTE ON FUNCTION api.get_tooldata TO api_user;
ALTER DEFAULT PRIVILEGES GRANT EXECUTE ON FUNCTIONS TO PUBLIC;

-- Create synthetic data for query testing
-- Function to generate synthetic data into channeldata, input is channel id and number of data points
DROP FUNCTION IF EXISTS api.gen_data;
CREATE OR REPLACE FUNCTION api.gen_data(channel CHAR(35), datapoints INT, days_offset INT DEFAULT 0, tool CHAR(35) DEFAULT NULL)
-- Return message if channel and tool do not exist
RETURNS TEXT AS $$
DECLARE
  create_msg TEXT;
  insert_msg TEXT;
  _tool CHAR(35);
  insert_format_query TEXT;

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

  -- Raise Error if channel exists and tool does not -- TODO: Check if this is correct
  IF EXISTS (SELECT * FROM api.channels WHERE osw_channel = channel AND osw_tool <> _tool) THEN
    RAISE EXCEPTION 'Channel exists but tool does not match!';
  END IF;

  -- Create channel if not exists but tool exists
  IF EXISTS (SELECT 1 FROM api.channels WHERE osw_channel <> channel AND osw_tool = _tool) THEN
    -- Case 1 Channel does not exist at all and tool exists -> create channel with tool 
    IF NOT EXISTS (SELECT 1 FROM api.channels WHERE osw_channel = channel) THEN
      -- ! Different line in schema 3, cause association of tool and channel is in table tools instead of channels
      -- INSERT INTO api.channels (osw_channel, osw_tool) VALUES (channel, _tool); -- ! SCHEMA 4
      PERFORM api.create_channel(_tool, channel); -- ! SCHEMA 3
      -- message that channel and tool were created
      RAISE NOTICE 'Channel for exisiting Tool created successfully!'; 
      create_msg := 'Channel for existing Tool and ';
    END IF;
  END IF;

  -- Create channel and tool if both do not exist
  -- ! Different line in schema 3, cause association of tool and channel is in table tools instead of channels
  -- IF NOT EXISTS (SELECT 1 FROM api.channels WHERE osw_channel = channel AND osw_tool = _tool) THEN -- ! SCHEMA 4
  IF NOT EXISTS (SELECT 1 FROM api.tools WHERE osw_tool = _tool) AND NOT EXISTS (SELECT 1 FROM api.channels WHERE osw_channel = channel) THEN -- ! SCHEMA 3
    PERFORM api.create_tool(_tool, channel);
    -- message that channel and tool were created
    RAISE NOTICE 'Channel and Tool created successfully!'; 
    create_msg := 'Channel, Tool and ';
  END IF;
  
  -- ! Different mechanism in schema 3, cause data is stored in table with channel name UUID of 
  insert_format_query:= format('
        INSERT INTO api.%I(ts, data)
        SELECT
            ''2024-01-01T00:00:00.000000+00''::TIMESTAMPTZ + (%s * interval ''1 day'') + (generate_series(1, %s) ) * interval ''1 microseconds'',
            (''{"value":''||(random()*100)::real||''}'')::json
        ', channel, days_offset, datapoints);
  -- show query
  RAISE NOTICE 'Executed Format Query: %', insert_format_query;
  EXECUTE insert_format_query;
  
  -- message that data was created
  RAISE NOTICE 'Data generated successfully!';
  insert_msg := 'Data generated successfully!';

  RETURN create_msg || insert_msg;
END;
$$ LANGUAGE plpgsql;

-- SELECT api.gen_data('OSW24f9c902423f4733a96cc26sctest0c1', 1000, 1, 'OSW24f9c902423f4733a96cc26sctest0t1');
