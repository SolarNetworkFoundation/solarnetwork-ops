-- base read-only group
CREATE ROLE solar WITH
  NOLOGIN
  NOSUPERUSER
  INHERIT
  NOCREATEDB
  NOCREATEROLE
  NOREPLICATION;

-- group for write-access to data input
CREATE ROLE solarinput WITH
  NOLOGIN
  NOSUPERUSER
  INHERIT
  NOCREATEDB
  NOCREATEROLE
  NOREPLICATION;
GRANT solar TO solarinput;

-- group for write-access to data input
CREATE ROLE solarjobs WITH
  NOLOGIN
  NOSUPERUSER
  INHERIT
  NOCREATEDB
  NOCREATEROLE
  NOREPLICATION;
GRANT solar TO solarjobs;

-- group for read-access to node data
CREATE ROLE solarquery WITH
  NOLOGIN
  NOSUPERUSER
  INHERIT
  NOCREATEDB
  NOCREATEROLE
  NOREPLICATION;
GRANT solar TO solarquery;

-- group for write-access to user maintenance, data import
CREATE ROLE solaruser WITH
  NOLOGIN
  NOSUPERUSER
  INHERIT
  NOCREATEDB
  NOCREATEROLE
  NOREPLICATION;
GRANT solar TO solaruser;
