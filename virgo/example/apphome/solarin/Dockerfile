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

RUN mkdir -p /opt/var/DeveloperCA && \
    chown virgo:virgo /opt/var/DeveloperCA

COPY --chown=virgo:virgo . /opt/virgo

EXPOSE 9083
EXPOSE 9703

USER virgo

CMD /opt/virgo/bin/sn-start.sh
