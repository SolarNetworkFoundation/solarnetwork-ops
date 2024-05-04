js_import headers from js/headers.js;
js_set $req_headers_json headers.req_headers_json;

log_format solarin escape=json '$remote_addr $time_iso8601 $request $status $body_bytes_sent '
                   '"$http_user_agent" "$ssl_client_s_dn" '
                   '$request_time $upstream_response_time '
                   '"$req_headers_json"';
