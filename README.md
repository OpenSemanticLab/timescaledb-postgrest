# TimescaleDB PostgREST

Table of Contents

- [TimescaleDB PostgREST](#timescaledb-postgrest)
  - [Database Schema](#database-schema)
  - [Dataset Example](#dataset-example)

## Database Schema

- Each OSW Tool own endpoint, osw_channel is direct attribute of each osw_tool table/endpoint
- in this version it is not possible to query all data from all tools (either dynamic/sub query function or combined channel references reqired)

```mermaid
erDiagram
  a[API_SCHEMA_2]
  t[tools] {
    CHAR(35) osw_tool PK
  }
  tv[tools_view] {
    CHAR(35) osw_tool
  }
  fcte[func_create_tool_endpoint] {
    CHAR(35) osw_tool
  }
  fct[func_create_tool] {
    CHAR(35) osw_tool
  }
  fcts[func_create_tools] {
    CHAR(35)[] osw_tool
  }
  nt[n_osw_tools] {
    CHAR(35) osw_channel
    TIMESTAMP ts
    JSONB data
  }
  a ||--o| t : has_internal
  a ||--o| fcte : has_internal
  a ||--o| fct : exposes
  a ||--o| fcts : exposes
  a ||--o| tv : exposes
  a ||--o| nt : exposes
  tv ||--o| t : reads
  fct ||--o| fcte : performs
  fct ||--o| t : inserts
  fcts ||--o| fcte : performs
  fcts ||--o| t : inserts
  fcte ||--o| nt : creates
```

## Dataset Example

Tools, each labled by OSW-UUID for each Tool as own Endpoints
representing hypertables in postgres are used in this schema.
Channels as part of tools used are also labled by OSW-UUIDs.
Data Objects on 'api.<TOOL_OSW_UUID>' have format:

```json
{
    "osw_channel": "<CHANNEL_OSW_UUID>",
    "ts": "<TIMESTAMP>",
    "data": {},
}
```


## Prerequisites

- Docker, Docker Compose
- Local data directory or linked directory (optionally use docker volume)


### Using Mounted Directory

Create local data directory with right permissions, for instance 1st pgdata directory:

```bash
sudo mkdir -p /mnt/tsdb-pgrst-1_pgdata
sudo chown -R 1000:1000 /mnt/tsdb-pgrst-1_pgdata
```

Symlink to local directory to be used by docker-compose:

```bash
sudo ln -s /mnt/tsdb-pgrst-1_pgdata pgdata
```
