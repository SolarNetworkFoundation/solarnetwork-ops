FROM openjdk:8-jre-slim

RUN groupadd -g 999 virgo && \
    useradd -r -u 999 -g virgo virgo

RUN mkdir -p /opt/var/DeveloperCA && \
    chown virgo:virgo /opt/var/DeveloperCA

COPY --chown=virgo:virgo . /opt/virgo

EXPOSE 9082
EXPOSE 9702

USER virgo

CMD /opt/virgo/bin/sn-start.sh
