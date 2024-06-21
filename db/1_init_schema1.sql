-- 1_init_schema1.sql

-- Authors: 
  -- Andreas Räder, https://github.com/raederan

SET search_path TO api;

----------- OSW REAL WORLD SCENARIO --------------
-- https://www.uuidgenerator.net/version4

-- single data channels (sources) table for reference
DROP TABLE IF EXISTS api.channels CASCADE;
CREATE TABLE api.channels(
  id SERIAL PRIMARY KEY, 
  osw_channel CHAR(35) NOT NULL,
  osw_tool CHAR(35) NOT NULL
);
-- GRANT SELECT on api.channels to api_anon;
GRANT ALL on api.channels to api_user;
GRANT USAGE, SELECT, UPDATE ON SEQUENCE channels_id_seq TO api_user;

-- Function to check if a tool endpoint is allowed to be created
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
DROP FUNCTION IF EXISTS api.tool_condition(osw_tool CHAR(35));
CREATE OR REPLACE FUNCTION api.tool_condition(osw_tool CHAR(35))
RETURNS BOOLEAN AS
$$
DECLARE
  tool_entry_exists BOOLEAN; -- check if tool exists in api.channels
  tool_table_exists BOOLEAN; -- check if table of osw_tool name exists
  tool_allowed BOOLEAN; -- only if tool_entry_exists and not tool_table_exists
BEGIN
  SELECT EXISTS(SELECT t1.osw_tool FROM api.channels AS t1 WHERE t1.osw_tool = $1 LIMIT 1) INTO tool_entry_exists;
  SELECT EXISTS(
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'api'
    AND table_name = $1
  ) INTO tool_table_exists;
  tool_allowed := tool_entry_exists AND NOT tool_table_exists;
  RETURN tool_allowed;
END;
$$
LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION api.tool_condition(char) TO api_user;
ALTER DEFAULT PRIVILEGES GRANT EXECUTE ON FUNCTIONS TO PUBLIC;

-- Endpoint to create a new data channel endpoint
-- !INDEX ON TS, MAYBE CHANGE TO UUID OR ADD INDEX ON UUID
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
DROP FUNCTION IF EXISTS api.create_tool_endpoint(osw_tool CHAR(35));
CREATE OR REPLACE FUNCTION api.create_tool_endpoint(osw_tool CHAR(35)) RETURNS TEXT AS
$$
BEGIN
  IF api.tool_condition(osw_tool) THEN
    EXECUTE format('CREATE TABLE IF NOT EXISTS api.%I (ts TIMESTAMPTZ NOT NULL, id INTEGER, data JSONB, FOREIGN KEY (id) REFERENCES api.channels (id))', osw_tool);
    EXECUTE format('SELECT api.create_hypertable(''api.%I'', ''ts'')', osw_tool);
    EXECUTE format('GRANT SELECT on api.%I to api_anon', osw_tool);
    EXECUTE format('GRANT ALL on api.%I to api_user', osw_tool);
    RETURN 'OSW tool created successfully: ' || osw_tool;
  ELSE
    RETURN 'Not allowed to create OSW tool: ' || osw_tool || ', endpoint already exists or not referenced in api.channels';
  END IF;
END;
$$
LANGUAGE plpgsql;
-- GRANT EXECUTE ON FUNCTION api.create_tool_endpoint TO api_anon;
GRANT EXECUTE ON FUNCTION api.create_tool_endpoint TO api_user;
ALTER DEFAULT PRIVILEGES GRANT EXECUTE ON FUNCTIONS TO PUBLIC;
GRANT EXECUTE ON FUNCTION api.create_hypertable (regclass, _timescaledb_internal.dimension_info, boolean , boolean, boolean) TO api_user;
GRANT EXECUTE ON FUNCTION api.create_hypertable (regclass, name, name, integer, name, name, anyelement, boolean, boolean, regproc, boolean, text, regproc, regproc) TO api_user;
GRANT EXECUTE ON FUNCTION _timescaledb_functions.insert_blocker() TO api_user;

-- create a view on table api.channels
CREATE OR REPLACE VIEW api.channels_view AS
SELECT id, osw_channel, osw_tool FROM api.channels;
GRANT SELECT ON api.channels_view TO api_anon;
GRANT all ON api.channels_view TO api_user;

DROP FUNCTION IF EXISTS api.insert_data_array(CHAR(35)[], TIMESTAMPTZ[], JSONB[]);
CREATE OR REPLACE FUNCTION api.insert_data_array(osw_channel CHAR(35)[], ts TIMESTAMPTZ[], data JSONB[])
RETURNS void AS
$$
DECLARE
  _osw_tool CHAR(35);
  _id INTEGER;
  _json_data JSONB;
  _osw_channel CHAR(35)[];
BEGIN
  _osw_channel := osw_channel; -- must be redeclared to be used in the loop to avoid var/table conflict
  FOR i IN 1..array_length(_osw_channel, 1)
  LOOP
    SELECT t1.osw_tool, t1.id INTO _osw_tool, _id FROM api.channels AS t1 WHERE t1.osw_channel = _osw_channel[i];
    IF _osw_tool IS NOT NULL AND _id IS NOT NULL THEN
      EXECUTE format('INSERT INTO api.%I (ts, id, data) VALUES (%L, %L, %L)', _osw_tool, ts[i], _id, data[i]);
    END IF;
  END LOOP;  
END;
$$
LANGUAGE plpgsql;

-- to be tested
DROP FUNCTION IF EXISTS api.insert_data_json(JSON[]);
CREATE OR REPLACE FUNCTION api.insert_data_json(payload JSON[])
RETURNS void AS
$$
DECLARE
  _osw_tool CHAR(35);
  _id INTEGER;
BEGIN
  FOR i IN 1..array_length(payload, 1)
  LOOP
    SELECT t1.osw_tool, t1.id INTO _osw_tool, _id 
    FROM api.channels AS t1 
    WHERE t1.osw_channel = payload[i]->>'osw_channel';
    IF _osw_tool IS NOT NULL AND _id IS NOT NULL THEN  
    EXECUTE format('INSERT INTO api.%I (ts, id, data) VALUES (%L, %L, %L)',
      _osw_tool, payload[i]->>'ts', _id, payload[i]->>'data');
    END IF;
  END LOOP;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION api.watch_channels() RETURNS TRIGGER AS
$$
BEGIN
  IF NEW.osw_tool IS NOT NULL THEN
    PERFORM api.create_tool_endpoint(NEW.osw_tool);
  END IF;
  RETURN NEW;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER tool_endpoint_trigger
AFTER INSERT ON api.channels
FOR EACH ROW
EXECUTE FUNCTION api.watch_channels();


-- Create a function to get the data of all channels of a given osw_tool including the osw_channel but without id
DROP FUNCTION IF EXISTS api.get_tool_data(CHAR(35));
CREATE OR REPLACE FUNCTION api.get_tool_data(osw_tool CHAR(35))
RETURNS TABLE (osw_channel CHAR(35), ts TIMESTAMPTZ, data JSONB) AS
$$
BEGIN
  RETURN QUERY EXECUTE format(
    'SELECT t1.osw_channel, t2.ts, t2.data
     FROM api.channels AS t1
     JOIN api.%I AS t2
     ON t1.id = t2.id', osw_tool);
END;
$$
LANGUAGE plpgsql;

-- SELECT * FROM api.get_tool_data('OSWe452d8694bf44424b24600a6d588b4ba');

-- SELECT osw_channel, ts, data FROM api.get_tool_data('OSWe452d8694bf44424b24600a6d588b4ba') ORDER BY ts DESC  
-- LIMIT 10;

-- SELECT ts, data FROM api.get_tool_data('OSWe452d8694bf44424b24600a6d588b4ba') 
-- WHERE osw_channel = 'OSWe725496c096d4654aa3b174516ff36dc'
-- ORDER BY ts DESC  
-- LIMIT 10;

-- -- Create a function to get the data of all channels of a given osw_tool including the osw_channel but without id and additional parameter to set a limit 
-- DROP FUNCTION IF EXISTS api.get_tool_data(CHAR(35), INTEGER);
-- CREATE OR REPLACE FUNCTION api.get_tool_data(osw_tool CHAR(35), _limit INTEGER DEFAULT 100)
-- RETURNS TABLE (osw_channel CHAR(35), ts TIMESTAMPTZ, data JSONB) AS
-- $$
-- DECLARE
--   _osw_id INTEGER;
-- BEGIN
--   SELECT id INTO _osw_id FROM api.channels AS t1 WHERE t1.osw_tool = $1;
--   RETURN QUERY EXECUTE format('SELECT t1.osw_channel, t2.ts, t2.data FROM api.channels AS t1, api.%I AS t2 WHERE t1.id = t2.id LIMIT %L', $1, $2);
-- END;
-- $$
-- LANGUAGE plpgsql;

-- SELECT * FROM api.get_tool_data('OSWe452d8694bf44424b24600a6d588b4ba');

-- Create a function to get all data of a channel by osw_channel and timestamp range
DROP FUNCTION IF EXISTS api.get_channel_data_range(CHAR(35), TIMESTAMPTZ, TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION api.get_channel_data_range(osw_channel CHAR(35), start_ts TIMESTAMPTZ, end_ts TIMESTAMPTZ)
RETURNS TABLE (ts TIMESTAMPTZ, data JSONB) AS
$$
DECLARE
  _osw_tool CHAR(35);
  _osw_id INTEGER;
BEGIN
  SELECT osw_tool INTO _osw_tool FROM api.channels AS t1 WHERE t1.osw_channel = $1;
  SELECT id INTO _osw_id FROM api.channels AS t2 WHERE t2.osw_channel = $1;
  RETURN QUERY EXECUTE format(
    'SELECT ts, data
     FROM api.%I
     WHERE id = %L
     AND ts BETWEEN %L AND %L', _osw_tool, _osw_id, start_ts, end_ts);
END;
$$
LANGUAGE plpgsql;

-- SELECT * FROM api.get_channel_data_range('OSWe725496c096d4654aa3b174516ff36dc', now() - interval '1 day', now());



-- Create a function to query channel data by osw_channel on table api.OSW* by given osw_tool and id from api.channels
DROP FUNCTION IF EXISTS api.get_channel_data(CHAR(35));
CREATE OR REPLACE FUNCTION api.get_channel_data(osw_channel CHAR(35))
RETURNS TABLE (ts TIMESTAMPTZ, data JSONB) AS
$$
DECLARE
  _osw_tool CHAR(35);
  _osw_id INTEGER;
BEGIN
  SELECT osw_tool INTO _osw_tool FROM api.channels AS t1 WHERE t1.osw_channel = $1;
  SELECT id INTO _osw_id FROM api.channels AS t2 WHERE t2.osw_channel = $1;
  RETURN QUERY EXECUTE format('SELECT ts, data FROM api.%I WHERE id = %L', _osw_tool, _osw_id);
END;
$$
LANGUAGE plpgsql;

-- SELECT api.get_channel_data('OSWe725496c096d4654aa3b174516ff36dc');




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
  _id INTEGER;
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

  -- Raise Error if channel exists and tool does not
  IF EXISTS (SELECT * FROM api.channels WHERE osw_channel = channel AND osw_tool <> _tool) THEN
    RAISE EXCEPTION 'Channel exists but tool does not match!';
  END IF;

  -- Create channel if not exists but tool exists
  IF EXISTS (SELECT 1 FROM api.channels WHERE osw_channel <> channel AND osw_tool = _tool) THEN
    -- Case 1 Channel does not exist at all and tool exists -> create channel with tool
    IF NOT EXISTS (SELECT 1 FROM api.channels WHERE osw_channel = channel) THEN
      INSERT INTO api.channels (osw_channel, osw_tool) VALUES (channel, _tool);
      -- message that channel and tool were created
      RAISE NOTICE 'Channel for exisiting Tool created successfully!'; 
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
  
  SELECT id INTO _id FROM api.channels WHERE osw_channel = channel;
  -- Insert data into api."%osw_tool%" table
  insert_format_query:= format('
        INSERT INTO api.%I(id, ts, data)
        SELECT
            %s,
            ''2024-01-01T00:00:00.000000+00''::TIMESTAMPTZ + (%s * interval ''1 day'') + (generate_series(1, %s) ) * interval ''1 microseconds'',
            (''{"value":''||(random()*100)::real||''}'')::json
        ', tool, _id, days_offset, datapoints);
  -- show query
  RAISE NOTICE 'Executed Format Query: %', insert_format_query;
  EXECUTE insert_format_query;

  -- message that data was created
  RAISE NOTICE 'Data generated successfully!';
  insert_msg := 'Data generated successfully!';

  RETURN create_msg || insert_msg;
END;
$$ LANGUAGE plpgsql;


-- -- Test data generation (expected)
-- -- -------------------------------
-- -- Preset
-- -- ------
-- INSERT INTO api.channels (osw_channel, osw_tool) VALUES ('OSWe725496c096d4654aa3b174516ff36dc', 'OSWe725496c096d4654aa3b174516ff36t0');
-- -- Tests
-- -- ------
-- -- Test existing channel and associated tool (auto ref tool)
-- SELECT api.gen_data('OSWe725496c096d4654aa3b174516ff36dc', 100, 0);
-- -- Test new channel and new tool (auto create both)
-- SELECT api.gen_data('OSWe725496c096d4654aa3b174516ff36cn', 100, 0, 'OSWe725496c096d4654aa3b174516ff36tn');
-- -- Test new channel and existing tool (auto create channel)
-- SELECT api.gen_data('OSWe725496c096d4654aa3b174516ff36c1', 100, 0, 'OSWe725496c096d4654aa3b174516ff36tn');
-- -- Test existing channel and new tool (fail, no match channel and tool)
-- -- -- SELECT api.gen_data('OSWe725496c096d4654aa3b174516ff36dc', 100, 0, 'OSWe725496c096d4654aa3b174516ff36t9');
-- -- Test new channel and no tool (fail, no tool provided)
-- -- -- SELECT api.gen_data('OSWe725496c096d4654aa3b174516ff36no', 100, 0);

-- https://www.postgresql.org/docs/current/xfunc-volatility.html
-- VOLATILE: The function value can change even within a single table scan, so no optimizations can be made.
-- STABLE: The function will return the same results given the same arguments for all rows within a single table scan, so the result can be calculated once and used for all rows.
-- IMMUTABLE: The function will always return the same result given the same arguments, so the result can be calculated once and cached.