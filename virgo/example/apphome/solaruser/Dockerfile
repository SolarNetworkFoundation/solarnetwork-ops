FROM openjdk:8-jre-slim

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		# curl for getting AWS metadata
		curl \
		# jq for parsing AWS metadata
		jq \
		# ssh for admin
		openssh-server \
	; \
	rm -rf /var/lib/apt/lists/*

RUN mkdir /var/run/sshd

# SSH login fix. Otherwise user is kicked off after login
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

ENV NOTVISIBLE "in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile

RUN groupadd -g 999 virgo && \
    useradd -r -u 999 -g virgo -m -d /opt/virgo virgo

RUN mkdir -p /opt/var/DeveloperCA && \
    chown virgo:virgo /opt/var/DeveloperCA

COPY --chown=virgo:virgo . /opt/virgo

EXPOSE 22
EXPOSE 9081
EXPOSE 9701

CMD /opt/virgo/bin/sn-start-ssh.sh
