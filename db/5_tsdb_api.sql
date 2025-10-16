-- 5_tsdb_api.sql

-- Authors: 
  -- Andreas Räder, https://github.com/raederan

-- Set search path to api schema
SET search_path TO api;

-- Grant execute on time_bucket to api_user
GRANT EXECUTE ON FUNCTION api.time_bucket(interval, timestamptz) TO api_user;
-- Create RPC for timebucket including tool, channel, interval, start and end time using avg function
DROP FUNCTION IF EXISTS api.get_timebucket_avg(tool CHAR(35), channel CHAR(35), bucket_width INTERVAL, start_time TIMESTAMPTZ, end_time TIMESTAMPTZ, data_key TEXT);
CREATE FUNCTION api.get_timebucket_avg(tool CHAR(35), channel CHAR(35), bucket_width INTERVAL, start_time TIMESTAMPTZ, end_time TIMESTAMPTZ, data_key TEXT DEFAULT 'v')
RETURNS TABLE(bucket TIMESTAMPTZ, avg REAL) AS $$
BEGIN
    RETURN QUERY EXECUTE
        format(
            'SELECT api.time_bucket($1, ts) AS bucket, AVG((data->>%L)::real)::REAL
             FROM api.%I
             WHERE ch = $2 AND ts >= $3 AND ts < $4
             GROUP BY bucket
             ORDER BY bucket',
            data_key, tool
        )
    USING bucket_width, channel, start_time, end_time;
END;
$$ LANGUAGE plpgsql;
-- Grant authenticated api_user to execute the function
GRANT EXECUTE ON FUNCTION api.get_timebucket_avg(char, char, interval, timestamptz, timestamptz, text) TO api_user;
