FROM openjdk:8-jre-slim

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		# curl for getting AWS metadata
		curl \
		# jq for parsing AWS metadata
		jq \
	; \
	rm -rf /var/lib/apt/lists/*

RUN groupadd -g 999 virgo && \
    useradd -r -u 999 -g virgo virgo

COPY --chown=virgo:virgo . /opt/virgo

EXPOSE 9082
EXPOSE 9702

USER virgo

CMD /opt/virgo/bin/sn-start.sh
