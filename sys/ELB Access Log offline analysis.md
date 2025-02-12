# ELB Access log offline analysis

[DuckDB](https://duckdb.org/) has tools useful for AWS Elastic Load Balancer (ELB) access log
analysis. First download the CSV access logs from S3. Then you can load them into a database:

```sh
# create/open new file database
duckdb logs.db
```

Then load the CSV into a `logs` table (note the `read_csv_auto('*/*.log.gz'` part that determines
which log files are loaded):

```sql
create table logs as select * from 
  read_csv_auto('2025/01/*/*.log.gz'
  , delim=' '
  , types = { 
   'type': 'VARCHAR', 
   'time': 'TIMESTAMP', 
   'elb': 'VARCHAR', 
   'client_port': 'VARCHAR', 
   'target_port': 'VARCHAR', 
   'request_processing_time': 'FLOAT', 
   'target_processing_time': 'FLOAT', 
   'response_processing_time': 'FLOAT', 
   'elb_status_code': 'VARCHAR', 
   'target_status_code': 'VARCHAR', 
   'received_bytes': 'BIGINT', 
   'sent_bytes': 'BIGINT', 
   'request': 'VARCHAR', 
   'user_agent': 'VARCHAR', 
   'ssl_cipher': 'VARCHAR', 
   'ssl_protocol': 'VARCHAR', 
   'target_group_arn': 'VARCHAR', 
   'trace_id': 'VARCHAR', 
   'domain_name': 'VARCHAR', 
   'chosen_cert_arn': 'VARCHAR', 
   'matched_rule_priority': 'VARCHAR', 
   'request_creation_time': 'TIMESTAMP', 
   'actions_executed': 'VARCHAR', 
   'redirect_url': 'VARCHAR', 
   'error_reason': 'VARCHAR', 
   'target_port_list': 'VARCHAR', 
   'target_status_code_list': 'VARCHAR', 
   'classification': 'VARCHAR', 
   'classification_reason': 'VARCHAR' 
  }
  , names=[
    'type', 'time', 'elb', 'client_port', 'target_port',
    'request_processing_time', 'target_processing_time', 'response_processing_time',
    'elb_status_code', 'target_status_code', 'received_bytes', 'sent_bytes', 'request',
    'user_agent', 'ssl_cipher', 'ssl_protocol', 'target_group_arn', 'trace_id', 'domain_name',
    'chosen_cert_arn', 'matched_rule_priority', 'request_creation_time', 'actions_executed',
    'redirect_url', 'error_reason', 'target_port_list', 'target_status_code_list',
    'classification', 'classification_reason'
  ]
  , union_by_name=true
);
```

From there you can run SQL queries, e.g. find all HTTP `5xx` status responses: 

```sql
select time, elb_status_code, target_status_code, user_agent, request
from logs
where elb_status_code = '5%' or target_status_code like '5%';
```

## Insert more data

Can insert more data like this:

```sql
insert into logs (type, time, elb, client_port, target_port,
  request_processing_time, target_processing_time, response_processing_time,
  elb_status_code, target_status_code, received_bytes, sent_bytes, request,
  user_agent, ssl_cipher, ssl_protocol, target_group_arn, trace_id, domain_name,
  chosen_cert_arn, matched_rule_priority, request_creation_time, actions_executed,
  redirect_url, error_reason, target_port_list, target_status_code_list,
  classification, classification_reason)
  (select type, time, elb, client_port, target_port,
  request_processing_time, target_processing_time, response_processing_time,
  elb_status_code, target_status_code, received_bytes, sent_bytes, request,
  user_agent, ssl_cipher, ssl_protocol, target_group_arn, trace_id, domain_name,
  chosen_cert_arn, matched_rule_priority, request_creation_time, actions_executed,
  redirect_url, error_reason, target_port_list, target_status_code_list,
  classification, classification_reason 
  from read_csv_auto('2025/01/*/*.log.gz'
       , delim=' '
       , types = { 
        'type': 'VARCHAR', 
        'time': 'TIMESTAMP', 
        'elb': 'VARCHAR', 
        'client_port': 'VARCHAR', 
        'target_port': 'VARCHAR', 
        'request_processing_time': 'FLOAT', 
        'target_processing_time': 'FLOAT', 
        'response_processing_time': 'FLOAT', 
        'elb_status_code': 'VARCHAR', 
        'target_status_code': 'VARCHAR', 
        'received_bytes': 'BIGINT', 
        'sent_bytes': 'BIGINT', 
        'request': 'VARCHAR', 
        'user_agent': 'VARCHAR', 
        'ssl_cipher': 'VARCHAR', 
        'ssl_protocol': 'VARCHAR', 
        'target_group_arn': 'VARCHAR', 
        'trace_id': 'VARCHAR', 
        'domain_name': 'VARCHAR', 
        'chosen_cert_arn': 'VARCHAR', 
        'matched_rule_priority': 'VARCHAR', 
        'request_creation_time': 'TIMESTAMP', 
        'actions_executed': 'VARCHAR', 
        'redirect_url': 'VARCHAR', 
        'error_reason': 'VARCHAR', 
        'target_port_list': 'VARCHAR', 
        'target_status_code_list': 'VARCHAR', 
        'classification': 'VARCHAR', 
        'classification_reason': 'VARCHAR' 
       }
       , names=[
         'type', 'time', 'elb', 'client_port', 'target_port',
         'request_processing_time', 'target_processing_time', 'response_processing_time',
         'elb_status_code', 'target_status_code', 'received_bytes', 'sent_bytes', 'request',
         'user_agent', 'ssl_cipher', 'ssl_protocol', 'target_group_arn', 'trace_id', 'domain_name',
         'chosen_cert_arn', 'matched_rule_priority', 'request_creation_time', 'actions_executed',
         'redirect_url', 'error_reason', 'target_port_list', 'target_status_code_list',
         'classification', 'classification_reason'
       ]
     , union_by_name=true
  ));
```

## Time bucket aggregates

First here's a handy view to extract the URL path from the `request` column, along with a few other
columns:

```sql
create or replace view logs_url as
select time
	, target_port
	, request_processing_time
	, target_processing_time
	, target_status_code
	, elb_status_code
	, received_bytes
	, sent_bytes
	, request
	, regexp_extract(request, 'https://data.solarnetwork.net:443([^? ]+)', 1) as url
from logs;
```

There here's a query that shows a count of requests for a given URL path, by day:

```sql
select time_bucket(interval '1 day', time) as time
  , url
  , count(*) as cnt
  , avg(case when target_processing_time < 0 then null else target_processing_time end) AS avg_target_processing_time
  , mode(case target_status_code when '-' then 0 else cast(target_status_code as integer) end) AS most_target_status_code
  , mode(cast(elb_status_code as integer)) AS most_elb_status_code
  , cast(avg(received_bytes) as integer) AS avg_received_bytes
  , cast(avg(sent_bytes) as integer) AS avg_sent_bytes
from logs_url
where target_port like '%:9081' and url = '/solaruser/api/v1/sec/datum/auxiliary'
and time between '2024-01-01 13:00:00Z' and '2025-02-12 13:00:00Z'
group by time_bucket(interval '1 day', time), url
order by time, cnt desc;
```

Or, broken down by 5-minute buckets and url:

```sql
select time_bucket(interval '5 minutes', time) as time
  , url
  , count(*) as cnt
  , round(avg(case when target_processing_time < 0 then null else target_processing_time end), 2) AS avg_processing_time
  , mode(case target_status_code when '-' then 0 else cast(target_status_code as integer) end) AS most_status_code
  , mode(cast(elb_status_code as integer)) AS most_elb_status_code
  , cast(avg(received_bytes) as integer) AS avg_received_bytes
  , cast(avg(sent_bytes) as integer) AS avg_sent_bytes
from logs_url
where target_port like '%:9081'
and time between '2025-02-11 23:15:00Z' and '2025-02-11 23:25:00Z'
group by time_bucket(interval '5 minutes', time), url
order by time, cnt desc;
```
```
┌─────────────────────┬──────────────────────────────────────────────────────────────┬───────┬─────────────────────┬──────────────────┬──────────────────────┬────────────────────┬────────────────┐
│        time         │                             url                              │  cnt  │ avg_processing_time │ most_status_code │ most_elb_status_code │ avg_received_bytes │ avg_sent_bytes │
│      timestamp      │                           varchar                            │ int64 │       double        │      int32       │        int32         │       int32        │     int32      │
├─────────────────────┼──────────────────────────────────────────────────────────────┼───────┼─────────────────────┼──────────────────┼──────────────────────┼────────────────────┼────────────────┤
│ 2025-02-11 23:15:00 │ /solaruser/api/v1/sec/nodes                                  │  1343 │               12.41 │              200 │                  200 │                404 │          10012 │
│ 2025-02-11 23:15:00 │ /solaruser/api/v1/sec/datum/auxiliary                        │   148 │                 1.0 │              200 │                  200 │               1062 │            610 │
│ 2025-02-11 23:15:00 │ /solaruser/api/v1/sec/instr/add                              │   133 │                3.57 │              200 │                  200 │                619 │            598 │
│ 2025-02-11 23:15:00 │ /solaruser/api/v1/sec/user/events                            │     7 │               14.28 │              200 │                  200 │                130 │        1562770 │
│ 2025-02-11 23:15:00 │ /solaruser/ping                                              │     3 │                     │                0 │                  504 │                 18 │            202 │
│ 2025-02-11 23:15:00 │ /solaruser/api/v1/sec/instr/add/OCPP_v16                     │     3 │                0.71 │              200 │                  200 │                919 │           1192 │
│ 2025-02-11 23:15:00 │ /solaruser/api/v1/sec/instr/view                             │     2 │                 0.0 │              200 │                  200 │                349 │           1278 │
│ 2025-02-11 23:15:00 │ /solaruser/api/v1/sec/user/c2c/datum-streams/46/latest-datum │     2 │                3.14 │              200 │                  200 │                124 │            558 │
│ 2025-02-11 23:15:00 │ /solaruser/api/v1/sec/user/c2c/datum-streams                 │     1 │                0.03 │              200 │                  200 │                177 │           2674 │
│ 2025-02-11 23:15:00 │ /solaruser/api/v1/sec/user/ocpp/sessions/incomplete/238      │     1 │                0.03 │              200 │                  200 │                360 │            699 │
│ 2025-02-11 23:20:00 │ /solaruser/api/v1/sec/nodes                                  │  2624 │               23.86 │                0 │                  502 │                404 │            880 │
│ 2025-02-11 23:20:00 │ /solaruser/api/v1/sec/datum/auxiliary                        │  1161 │                     │                0 │                  502 │                810 │            166 │
│ 2025-02-11 23:20:00 │ /solaruser/api/v1/sec/instr/add                              │   143 │                17.6 │                0 │                  502 │                619 │            441 │
│ 2025-02-11 23:20:00 │ /solaruser/api/v1/sec/user/ocpp/sessions/incomplete/238      │     2 │                     │                0 │                  502 │                360 │            277 │
│ 2025-02-11 23:20:00 │ /solaruser/api/v1/sec/user/ocpp/sessions/incomplete/160      │     2 │                 0.7 │                0 │                  502 │                360 │            392 │
│ 2025-02-11 23:20:00 │ /solaruser/api/v1/sec/user/ocpp/sessions/incomplete/115      │     1 │                     │                0 │                  502 │                360 │            277 │
│ 2025-02-11 23:20:00 │ /solaruser/api/v1/sec/instr/view                             │     1 │                0.13 │              200 │                  200 │                349 │           1280 │
├─────────────────────┴──────────────────────────────────────────────────────────────┴───────┴─────────────────────┴──────────────────┴──────────────────────┴────────────────────┴────────────────┤
│ 17 rows                                                                                                                                                                                8 columns │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```


# SolarQuery Proxy offline analysis

```sql
create table logs as select * from 
  read_csv_auto('*.zst', delim=' ', nullstr='-', ignore_errors=true,
  types = { 
   'remote_addr': 'VARCHAR', 
   'time': 'TIMESTAMP', 
   'method': 'VARCHAR',
   'request': 'VARCHAR', 
   'protocol': 'VARCHAR',
   'status_code': 'VARCHAR', 
   'sent_bytes': 'BIGINT', 
   'user_agent': 'VARCHAR', 
   'user_auth': 'VARCHAR', 
   'response_processing_time': 'FLOAT', 
   'target_processing_time': 'FLOAT'
  }, 
  names=[
    'remote_addr', 'time', 'method', 'request', 'protocol', 'status_code', 'sent_bytes',
    'user_agent', 'user_auth', 'response_processing_time', 'target_processing_time'
  ]
);
```

Handy view to extract security token:

```sql
create or replace view ulogs as
select remote_addr, time, method, request, protocol, status_code, sent_bytes,
    user_agent, regexp_extract(user_auth, 'Credential=([^,]+)(?:,|$)', 1) as user_auth,
    response_processing_time, target_processing_time
from logs;
```

Then some queries are easier, like total counts with average request time, by user:

```sql
select user_auth, count(*) as cnt, avg(target_processing_time) req_time from ulogs group by user_auth order by cnt desc;
```
```
┌──────────────────────┬────────┬──────────────────────┐
│      user_auth       │  cnt   │       req_time       │
│       varchar        │ int64  │        double        │
├──────────────────────┼────────┼──────────────────────┤
│ •••••••••••••••••••• │ 440107 │    5.538249516604449 │
│                      │ 199972 │    2.224748544307098 │
│ •••••••••••••••••••• │  45749 │   4.1000272670245765 │
│ •••••••••••••••••••• │   2531 │   0.1995285763990497 │
│ •••••••••••••••••••• │   1507 │ 0.052808228378352855 │
│ •••••••••••••••••••• │    123 │  0.05151020396709898 │
│ •••••••••••••••••••• │     59 │   1.5232142914298623 │
│ •••••••••••••••••••• │      6 │ 0.006666666905706127 │
│ •••••••••••••••••••• │      1 │    7.363999843597412 │
│ •••••••••••••••••••• │      1 │                  0.0 │
├──────────────────────┴────────┴──────────────────────┤
│ 10 rows                                    3 columns │
└──────────────────────────────────────────────────────┘
``` 
