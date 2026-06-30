# Local Kerberos and CERN/FNAL SSH Notes

This WSL Debian host can use one MIT Kerberos client configuration for both
Fermilab and CERN access. The repo snapshot did not include `/etc/krb5.conf`;
the installed config is based on Fermilab's official MIT Kerberos file, with
CERN realm/domain mappings kept explicit.

Source references:

- Fermilab Kerberos configuration files: <https://authentication.fnal.gov/krb5conf/>
- Fermilab MIT Kerberos config used as base: <https://authentication.fnal.gov/krb5conf/SL7/krb5.conf>
- CERN Kerberos access documentation: <https://linux.web.cern.ch/docs/kerberos-access/>
- CERN Kerberos config: <https://linux.web.cern.ch/docs/krb5.conf>

## Local Installation

Installed packages:

```bash
sudo apt-get install krb5-user dnsutils
```

Installed system config:

```bash
sudo install -m 0644 -o root -g root system/etc/krb5.conf /etc/krb5.conf
```

The previous generated Debian config was backed up on this host as:

```bash
/etc/krb5.conf.bak-20260630-before-fnal-cern
```

The Debian-generated file had `default_realm = DHCP.FNAL.GOV`, which is wrong
for this WSL host. That happened because the host FQDN is under
`dhcp.fnal.gov`.

## Principals

Use different principals for the two labs:

```bash
kinit arroyave@FNAL.GOV
kinit marroyav@CERN.CH
klist -A
```

`arroyave@FNAL.GOV` reaches the Fermilab KDC and asks for password
preauthentication. `marroyav@CERN.CH` reaches the CERN KDC and asks for password
preauthentication. That means local realm lookup and KDC connectivity are
working.

## SSH

The live `~/.ssh/config` keeps the GitHub key block and adds CERN aliases for:

```bash
ssh lxplus
ssh cern-lxtunnel
ssh np04-srv-017
ssh np04-srv-017-via-lxplus
ssh daphne15
```

The important rule is that short NP04 names expand to `*.cern.ch`; otherwise the
Kerberos client can request a service ticket in the wrong default realm.

Future Fermilab SSH aliases should use:

```sshconfig
User arroyave
```

and should be added only after the target gateway or login host is known.

## What Not To Copy Blindly

Do not rsync the entire `home/` tree from this repo onto a different account.
Several files came from `/home/neutrino` and contain machine-specific paths.
Use the SSH and Kerberos files as templates, not as a full workstation restore.
