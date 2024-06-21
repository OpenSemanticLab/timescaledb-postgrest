-- 2_init_schema2.sql

-- Authors: 
  -- Andreas Räder, https://github.com/raederan

SET search_path TO api;

-- ! ONLY IF ALL DATA OF ALL TOOLS SHOULD BE QUERYABLE 
-- Internal (GET -> View, POST -> RPC)
CREATE TABLE IF NOT EXISTS api.tools (
  osw_tool CHAR(35) PRIMARY KEY
);
-- GRANT SELECT, INSERT on api.tools TO api_user;

--------- ONLY FOR TESTING, REMOVE IN PRODUCTION ---------
-- GRANT SELECT on api.tools TO api_anon;
GRANT ALL on api.tools TO api_user;
----------------------------------------------------------

-- Endpoint to create a new data channel endpoint
-- !INDEX ON TS, MAYBE CHANGE TO UUID OR ADD INDEX ON UUID
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
DROP FUNCTION IF EXISTS api.create_tool_endpoint(osw_tool CHAR(35));
CREATE OR REPLACE FUNCTION api.create_tool_endpoint(osw_tool CHAR(35)) RETURNS void AS
$$
BEGIN
    EXECUTE format('CREATE TABLE IF NOT EXISTS api.%I (osw_channel CHAR(35), ts TIMESTAMPTZ NOT NULL, data JSONB)', osw_tool);
    EXECUTE format('SELECT api.create_hypertable(''api.%I'', ''ts'')', osw_tool);
    EXECUTE format('GRANT SELECT on api.%I to api_anon', osw_tool);
    EXECUTE format('GRANT ALL on api.%I to api_user', osw_tool);
END;
$$
LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION api.create_tool_endpoint TO api_user;
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
    INSERT INTO api.tools (osw_tool) VALUES (osw_tool); --! only if relation api.tools exists
		PERFORM api.create_tool_endpoint(osw_tool);
    RETURN 'OSW tool created successfully: ' || osw_tool;
END;
$$
LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION api.create_tool(char) TO api_anon;
GRANT EXECUTE ON FUNCTION api.create_tool(char) TO api_user;
ALTER DEFAULT PRIVILEGES GRANT EXECUTE ON FUNCTIONS TO PUBLIC;

-- Function to create a tool, input is array of osw_tools, returns status message
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
DROP FUNCTION IF EXISTS api.create_tools(osw_tools CHAR(35)[]);
CREATE OR REPLACE FUNCTION api.create_tools(osw_tools CHAR(35)[]) RETURNS TEXT AS
$$
DECLARE
		osw_tool CHAR(35);
BEGIN
		FOREACH osw_tool IN ARRAY osw_tools LOOP
				PERFORM api.create_tool(osw_tool);
		END LOOP;
		RETURN 'OSW tools created successfully: ' || array_to_string(osw_tools, ', ');
END;
$$
LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION api.create_tools(char[]) TO api_anon;
GRANT EXECUTE ON FUNCTION api.create_tools(char[]) TO api_user;
ALTER DEFAULT PRIVILEGES GRANT EXECUTE ON FUNCTIONS TO PUBLIC;

-- Create tools_view for public access
DROP VIEW IF EXISTS api.tools_view;
CREATE OR REPLACE VIEW api.tools_view AS
SELECT * FROM api.tools;
GRANT SELECT ON api.tools_view TO api_anon;
-- GRANT ALL ON api.tools_view TO api_user;
GRANT SELECT ON api.tools_view TO api_user;



-- Create synthetic data for query testing
-- Function to generate synthetic data into channeldata, input is channel id and number of data points
DROP FUNCTION IF EXISTS api.gen_data;
CREATE OR REPLACE FUNCTION api.gen_data(tool CHAR(35), channel CHAR(35), datapoints INT, days_offset INT DEFAULT 0)
-- Return message if channel and tool do not exist
RETURNS TEXT AS $$
DECLARE
  create_msg TEXT;
  insert_msg TEXT;
  insert_format_query TEXT;

BEGIN
  create_msg := '';
  insert_msg := '';


  IF NOT EXISTS (SELECT 1 FROM api.tools WHERE osw_tool = tool) THEN
    PERFORM api.create_tool(tool);
    -- message that channel and tool were created
    RAISE NOTICE 'Tool created successfully!'; 
    create_msg := 'Tool and ';
  END IF;
  
  -- ! Different mechanism in schema 3, cause data is stored in table with channel name UUID of 
  insert_format_query:= format('
        INSERT INTO api.%I(osw_channel, ts, data)
        SELECT
            %L,
            ''2024-01-01T00:00:00.000000+00''::TIMESTAMPTZ + (%s * interval ''1 day'') + (generate_series(1, %s) ) * interval ''1 microseconds'',
            (''{"value":''||(random()*100)::real||''}'')::json
        ', tool, channel, days_offset, datapoints);
  -- show query
  RAISE NOTICE 'Executed Format Query: %', insert_format_query;
  EXECUTE insert_format_query;
  
  -- message that data was created
  RAISE NOTICE 'Data generated successfully!';
  insert_msg := 'Data generated successfully!';

  RETURN create_msg || insert_msg;
END;
$$ LANGUAGE plpgsql;

-- SELECT api.gen_data('OSW24f9c902423f4733a96cc26sctest0t1', 'OSW24f9c902423f4733a96cc26sctest0c1', 1000, 1);