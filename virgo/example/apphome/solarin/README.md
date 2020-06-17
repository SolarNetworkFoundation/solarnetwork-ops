# SolarIn: SolarNetwork data ingestion

# SSL Setup

The SolarIn application requires X.509 client certificates for SolarNodes, which are provisioned
via the SolarUser application. The `configuration/tomcat-server.xml` file contains the SSL setup.
It expects a `configuration/central.jks` keystore that
contains a `web` private key and associated signed certificate and a `ca` CA public certificate. 

In addition, it expects a `configuration/central-trust.jks` keystore that includes the `ca` CA public
certificate.

Both keystores are expected to have a password of `dev123`. This is the password used by the 
SolarNetwork Developer CA, which the reference *solaruser* application deploys. Thus by starting
up the solaruser reference application, it will create the `central.jks` and `central-trust.jks` 
files and you can simply copy them into the `configuration` directory here.


# SSL Proxy

As SolarIn must have access to the node's X.509 client certificate, any SSL proxy sitting between
SolarIn and the node must forward this through so that the SolarIn servlet engine picks up the
certificate **and** sees the connection as being SSL.

## Apache httpd + Apache Tomcat

The AJP protocol works well for passing the appropriate SSL information, via the `mod_jk`
or `mod_proxy_ajp` plugins. The HTTP protocol can be used via `mod_proxy_http` as long as 
Tomcat is configured with the **Remote IP** and **SSL** valves. See the Nginx section next for
more information.

## Nginx + Apache Tomcat

Nginx does not support the AJP protocol, so must proxy via HTTP. In order to provide Tomcat  with
the necessary request details to treat the connection as SSL and provide the client certificate, it
must have the [Remote IP Valve][remote-ip-valve] and [SSL valve][ssl-valve] elements configured,
like this:

```xml
<Connector port="8080" protocol="HTTP/1.1" minSpareThreads="1" maxThreads="10"/>

<Engine name="Catalina" defaultHost="localhost">
	<Host name="localhost" unpackWARs="false" autoDeploy="false"
		liveDeploy="false" deployOnStartup="false" xmlValidation="false"/>

	<Valve className="org.apache.catalina.valves.SSLValve"/>

	<Valve className="org.apache.catalina.valves.RemoteIpValve"
		remoteIpHeader="X-Forwarded-For"
		protocolHeader="X-Forwarded-Proto"
		/>
</Engine>
```

Then in nginx the SSL details must be passed to Tomcat via `proxy_set_header` directives that 
match what the Remote IP and SSL valves expect. For example:

```
upstream solarin_cluster {
    server tomcat:8080;
}

server {
    listen 8683 ssl;
    server_name in.solarnetwork.net;

    location / {
        proxy_pass http://solarin_cluster;
        proxy_connect_timeout 1s;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header SSL_CLIENT_CERT $ssl_client_cert;
        proxy_set_header SSL_CIPHER $ssl_cipher;
        proxy_set_header SSL_SESSION_ID $ssl_session_id;
    }

    access_log /var/log/nginx/solarin_ssl_access.log main;
    error_log  /var/log/nginx/solarin_ssl_error.log info;

    ssl_certificate     /etc/ssl/certs/in.solarnetwork.net.crt;
    ssl_certificate_key /etc/ssl/private/in.solarnetwork.net.key;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:32m; # 128MB ~= 500k sessions
    ssl_session_tickets on;
    ssl_session_timeout 8h;

    ssl_verify_client optional;
    ssl_verify_depth 2;
    ssl_client_certificate /etc/ssl/certs/solarnetwork-ca-bundle.pem;
}

```


[remote-ip-valve]: http://tomcat.apache.org/tomcat-8.5-doc/config/valve.html#Remote_IP_Valve
[ssl-valve]: http://tomcat.apache.org/tomcat-8.5-doc/config/valve.html#SSL_Valve