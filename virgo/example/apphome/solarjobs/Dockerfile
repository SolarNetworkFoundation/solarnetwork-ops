FROM openjdk:8-jre-slim

RUN groupadd -g 999 virgo && \
    useradd -r -u 999 -g virgo virgo

COPY --chown=virgo:virgo . /opt/virgo

RUN mkdir -p /opt/var/DeveloperCA && \
    chown virgo:virgo /opt/var/DeveloperCA

EXPOSE 9080

USER virgo

CMD /opt/virgo/bin/sn-start.sh
