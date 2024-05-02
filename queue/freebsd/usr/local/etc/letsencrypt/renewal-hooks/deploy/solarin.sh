#!/bin/sh

set -e

daemon_cert_root=/mnt/cert-support/tls

for domain in $RENEWED_DOMAINS; do

		# Make sure the certificate and private key files are
		# never world readable, even just for an instant while
		# we're copying them into daemon_cert_root.
		umask 077

		cp -f "$RENEWED_LINEAGE/cert.pem" "$daemon_cert_root/$domain.cert"
		cp -f "$RENEWED_LINEAGE/chain.pem" "$daemon_cert_root/$domain.chain"
		cp -f "$RENEWED_LINEAGE/fullchain.pem" "$daemon_cert_root/$domain.fullchain"
		cp -f "$RENEWED_LINEAGE/privkey.pem" "$daemon_cert_root/$domain.key"

		# Apply the proper file ownership and permissions for
		# the daemon to read its certificate and key.
		chmod 440 "$daemon_cert_root/$domain.cert" \
				"$daemon_cert_root/$domain.chain" \
				"$daemon_cert_root/$domain.fullchain" \
				"$daemon_cert_root/$domain.key"
done

service nginx reload >/dev/null
