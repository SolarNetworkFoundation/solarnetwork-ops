UPDATE accounts SET 
	email = CONCAT(MD5(email), '@localhost')
	, name = MD5(name)
	, first_name_length = NULL
	, address1 = NULL
	, address2 = NULL
	, company_name = NULL
	, city = NULL
	, state_or_province = NULL
	, postal_code = NULL
	, phone = NULL;
UPDATE account_history SET
	email = MD5(email)
	, name = MD5(name)
	, first_name_length = NULL
	, address1 = NULL
	, address2 = NULL
	, company_name = NULL
	, city = NULL
	, state_or_province = NULL
	, postal_code = NULL
	, phone = NULL;
UPDATE bus_events_history SET
	event_json = REGEXP_REPLACE(event_json, '"(email|name|address1|address2|companyName|city|stateOrProvince|postalCode|phone)":"[^"]+"', '"\\1":"-"');

-- change passwords to 'foobar'
UPDATE kaui_tenants SET
	encrypted_api_secret = '7I9HC3EC6GkzJLd4qxgGQw==';
UPDATE tenants SET
	api_secret = 'aouTzxW0XU9NFR4/LB0MLmYObwL6tBm+by7+F4TjuxhwHM79vDTYABty/dBKxrEH03kxBEtE1Wy81QCfuguZAA=='
	, api_salt = 'jG63YIWC3jN+a8RpEKrJLQ==';
UPDATE users SET
	password = 'aouTzxW0XU9NFR4/LB0MLmYObwL6tBm+by7+F4TjuxhwHM79vDTYABty/dBKxrEH03kxBEtE1Wy81QCfuguZAA=='
	, password_salt = 'jG63YIWC3jN+a8RpEKrJLQ==';
