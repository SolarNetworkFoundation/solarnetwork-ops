log_format solarin '$remote_addr $time_iso8601 $request $status $body_bytes_sent '
                   '"$http_user_agent" "$ssl_client_s_dn" '
                   '$request_time $upstream_response_time '
                   '"$request_body_file"';
