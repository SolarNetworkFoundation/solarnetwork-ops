#!/bin/sh

set -e

daemon_cert_root=/sndb/home/17/tls
support_root=/mnt/cert-support/tls
for domain in $RENEWED_DOMAINS; do
		# Make sure the certificate and private key files are
		# never world readable, even just for an instant while
		# we're copying them into daemon_cert_root.
		umask 077

		cp -f "$RENEWED_LINEAGE/fullchain.pem" "$daemon_cert_root/$domain.fullchain"
		cp -f "$RENEWED_LINEAGE/privkey.pem" "$daemon_cert_root/$domain.key"

		# Apply the proper file ownership and permissions for
		# the daemon to read its certificate and key.
		chmod 440 "$daemon_cert_root/$domain.fullchain" \
				"$daemon_cert_root/$domain.key"

		chgrp postgres "$daemon_cert_root/$domain.fullchain" \
				"$daemon_cert_root/$domain.key"

		if [ -d "${support_root}" ]; then
			cp -a "$daemon_cert_root/$domain.fullchain" \
				"$daemon_cert_root/$domain.key" \
				"${support_root}/" 2>/dev/null
		fi
done
service postgresql reload >/dev/null
