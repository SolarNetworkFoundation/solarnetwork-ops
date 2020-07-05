UPDATE accounts SET email = CONCAT(REPLACE(email,'@','-AT-'), '@localhost');

-- change passwords to 'foobar'
UPDATE kaui_tenants SET
	encrypted_api_secret = '7I9HC3EC6GkzJLd4qxgGQw==';
UPDATE tenants SET
	api_secret = 'aouTzxW0XU9NFR4/LB0MLmYObwL6tBm+by7+F4TjuxhwHM79vDTYABty/dBKxrEH03kxBEtE1Wy81QCfuguZAA=='
	, api_salt = 'jG63YIWC3jN+a8RpEKrJLQ==';
UPDATE users SET
	password = 'aouTzxW0XU9NFR4/LB0MLmYObwL6tBm+by7+F4TjuxhwHM79vDTYABty/dBKxrEH03kxBEtE1Wy81QCfuguZAA=='
	, password_salt = 'jG63YIWC3jN+a8RpEKrJLQ==';
