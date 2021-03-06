CREATE USER solarauth WITH
	IN GROUP solarauthn
	LOGIN
	NOSUPERUSER
	NOCREATEDB
	NOCREATEROLE
	INHERIT
	NOREPLICATION
	CONNECTION LIMIT -1
	ENCRYPTED PASSWORD 'solarauth';

CREATE USER solarin WITH
	IN GROUP solarinput
	LOGIN
	NOSUPERUSER
	NOCREATEDB
	NOCREATEROLE
	INHERIT
	NOREPLICATION
	CONNECTION LIMIT -1
	ENCRYPTED PASSWORD 'solarinput';

CREATE USER solarmgmnt WITH
	IN GROUP solaruser
	LOGIN
	NOSUPERUSER
	NOCREATEDB
	NOCREATEROLE
	INHERIT
	NOREPLICATION
	CONNECTION LIMIT -1
	ENCRYPTED PASSWORD 'solarmgmnt';

CREATE USER solarquest WITH
	IN GROUP solarquery
	LOGIN
	NOSUPERUSER
	NOCREATEDB
	NOCREATEROLE
	INHERIT
	NOREPLICATION
	CONNECTION LIMIT -1
	ENCRYPTED PASSWORD 'solarquest';
	
CREATE USER solarworker WITH
	IN GROUP solarjobs
	LOGIN
	NOSUPERUSER
	NOCREATEDB
	NOCREATEROLE
	INHERIT
	NOREPLICATION
	CONNECTION LIMIT -1
	ENCRYPTED PASSWORD 'solarworker';
