# SolarNetwork Gnucash Accounting

For Gnucash accounting, a Postgres database server holds the data and a separate desktop VM with the
Gnucash application is used to access the data. The SolarNetwork service populates SNF invoices
into the database after they are generated, and the SNF accounting CLI tool can create credit notes
and insert payments.

As Gnucash requires exclusive access to the Postgres database while it runs, the application is
only run on demand, when needed. SolarNetwork will not update the database while Gnucash is
connected to the same database.

## Accounting UI

The Accounting UI machine does not need to run unless actively using Gnucash. The 
[sn-ec2-service](https://github.com/SolarNetworkFoundation/snf-ops-boot/blob/main/bin/sn-ec2-service.sh)
script can be used to manage the instance:

```sh
# check the running state of the instance (needs to be "running" to use)
sn-ec2-service accounting-state                                                                                                                                <main ✗>
stopped

# start the instance
sn-ec2-service accounting-start                                                                                                                                <main ✗>
Instance [Accounting UI] (i-09f40f5592eaf8ddf) state changed from stopped -> pending

# stop the instance
sn-ec2-service accounting-stop                                                                                                                                 <main ✗>
Instance [Accounting UI] (i-09f40f5592eaf8ddf) state changed from running -> stopping
```

## Connect with VNC port forwarding

While the instance is running, use the `accounting-connect` action to SSH to the instance,
with port `55901` forwarded to the VNC desktop server on the machine:

```sh
# SSH to the instance with 55901 port forwarding for VNC
sn-ec2-service accounting-connect                                                                                                                              <main ✗>
Connecting to instance [Accounting UI] @ 34.219.128.149
```

## VNC desktop

To run GnuCash, after connecting with `accounting-connect` point a VNC client at `localhost:55901`.
This will prompt for for the VNC password.

## GnuCash application

Once you've connected with VNC, you will see the VM desktop.
Use the **Applications > Office > GnuCash** menu to launch GnuCash. You will be prompted to enter
the database password. The password will have been copied into the clipboard for you, so just type
<kbd>Ctrl-V</kbd> to paste in the password.

> :warning: It is important you use the **File > Quit** menu in GnuCash to close the application
> when you are done, so the exclusive database lock it creates is released.


## Accounting DB

TODO

