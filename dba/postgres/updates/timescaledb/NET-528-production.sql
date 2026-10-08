ALTER FUNCTION solarnet.get_node_public_ssh_key(BIGINT) SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION solarnet.get_node_public_ssh_key(BIGINT) TO solarauthn;
