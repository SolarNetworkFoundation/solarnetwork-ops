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
