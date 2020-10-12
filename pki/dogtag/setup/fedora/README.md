# Tomcat restart timer

The `sn-pki-tomcatd-restart.timer` and associated service have been created because Dogtag 10.8 is
exhausting the available memory on our 1GB Fedora 32 system. It have been occurring consistently
roughly every 10 days, at which point the sytem becomes unresponsive. Restarting the service 
resolves the issue.

The timer/service have been installed in `/etc/systemd/system` and then enabled like this:

```sh
$ systemctl daemon-reload
$ systemctl enable sn-pki-tomcatd-restart.timer
$ systemctl start sn-pki-tomcatd-restart.timer
```

You can see the status via `systemctl list-timers`.
