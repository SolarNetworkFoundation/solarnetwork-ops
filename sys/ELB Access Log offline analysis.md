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
  read_csv_auto('*/*.log.gz', delim=' ', 
  types = { 
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
  }, 
  names=[
    'type', 'time', 'elb', 'client_port', 'target_port',
    'request_processing_time', 'target_processing_time', 'response_processing_time',
    'elb_status_code', 'target_status_code', 'received_bytes', 'sent_bytes', 'request',
    'user_agent', 'ssl_cipher', 'ssl_protocol', 'target_group_arn', 'trace_id', 'domain_name',
    'chosen_cert_arn', 'matched_rule_priority', 'request_creation_time', 'actions_executed',
    'redirect_url', 'error_reason', 'target_port_list', 'target_status_code_list',
    'classification', 'classification_reason'
  ]
);
```

From there you can run SQL queries, e.g. find all HTTP `5xx` status responses: 

```sql
select time, elb_status_code, target_status_code, user_agent, request
from logs
where elb_status_code = '5%' or target_status_code like '5%';
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
