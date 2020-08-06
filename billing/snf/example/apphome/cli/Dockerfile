FROM openjdk:11-jre-slim

RUN groupadd -g 999 app && \
    useradd -r -u 999 -g app -m -d /opt/app app

COPY --chown=app:app . /opt/app

EXPOSE 9021
EXPOSE 9022

USER app
WORKDIR /opt/app
CMD bin/app-start.sh
