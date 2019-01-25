add_header X-Proxy-Cache $upstream_cache_status;
add_header Access-Control-Allow-Origin '*';
add_header Access-Control-Allow-Methods 'GET,HEAD,POST,PUT,DELETE,OPTIONS,PATCH';
add_header Access-Control-Allow-Headers 'Authorization, Content-MD5, Content-Type, Digest, X-SN-Date';
add_header Access-Control-Max-Age 600;

