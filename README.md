# Cygnet

Connect Linux to FortiGate VPNs that ask for a one-time code, without FortiClient. It handles both
IPsec (IKEv2) and SSL VPN. Use it from the terminal or from a small GNOME-style app.

```
$ cygnet
Password for jane.doe:
Connecting to Head Office...
Password accepted. The gateway is now sending your code.
Enter the code: 123456
Checking the code...
Connected.
```

This is an unofficial community tool, not affiliated with Fortinet. It doesn't bypass two-factor
authentication: you still need a valid account and a real code. Only use it with VPNs you're
allowed to access, and check whether your organisation permits clients other than FortiClient.

## The problem

Many FortiGate dial-up VPNs use IKEv2 with a pre-shared key, a password, and a second factor. The
code is often emailed or texted, and only sent after the password has been accepted.

Stock strongSwan can't complete this login. The gateway asks for the code using a proprietary EAP
extension, which strongSwan rejects as malformed:

```
EAP Success/Failure has data
EAP verification failed
```

The login dies at that point, often before the code has even been sent. Appending the code to the
password doesn't help either, because you don't have a code yet.

## What this does

- Builds a patched strongSwan into `/opt/cygnet`. It's separate from any distro package, so
  system updates can't overwrite it.
- Asks for the code at the moment the gateway requests it, in your terminal or in the app.
- Keeps several connections, each one IPsec or SSL VPN, with its own gateway and username. One can
  be up at a time.
- Connects to SSL VPNs through [openfortivpn](https://github.com/adrienverge/openfortivpn). See
  [SSL VPN connections](#ssl-vpn-connections).
- Only runs its daemon while you need it.
- Never writes your code to disk. Your password is only saved if you choose that for an SSL VPN
  connection. Neither is ever passed on a command line.

## Does it fit your VPN?

For IPsec, it's designed for a FortiGate IKEv2 dial-up VPN using:

- a pre-shared key that authenticates the gateway
- EAP-MSCHAPv2 for your password
- a code requested over EAP-GTC, such as an email or SMS code

For SSL VPN, it works with a username and password, followed by a code from email, SMS or a token.

It doesn't cover SAML, client certificates or IKEv1.

What has been tested so far:

| Setup | Status |
|---|---|
| Ubuntu 24.04, one real FortiGate, split tunnel | Works |
| SSL VPN, Ubuntu 24.04, openfortivpn 1.21 | Password, code and certificate prompts tested against openfortivpn's helper protocol; not yet tried on a real gateway |
| Ubuntu 24.04, mock gateway, real systemd | Works |
| Manjaro, mock gateway, stand-in for systemd | Works; not yet tried on a real gateway |

The mock follows the protocol as described in
[strongSwan issue #3120](https://github.com/strongswan/strongswan/issues/3120), whose author reports
FortiOS 7.4.11 and 7.6.7 working. Other gateways may need different settings. See
[Troubleshooting](#troubleshooting).

## Install

Ubuntu/Debian and Manjaro/Arch are supported.

```sh
git clone https://github.com/Khalid-AlHajri/cygnet
cd cygnet
./install.sh
```

`install.sh` asks for `sudo` and installs openfortivpn from your distro. Then it downloads strongSwan,
checks its SHA-256, applies the patches and builds it. This takes a few minutes. It also installs the app. If you only want the command,
use `./install.sh --no-gui`.

If it stops starting after a system update, such as a new OpenSSL version, run `./install.sh`
again. Your connections are kept.

## Add a connection

In the app, press **+**. In a terminal, run `cygnet add`. First you choose IPsec or SSL VPN. Your
VPN admin can tell you which one to use. FortiClient lists SSL VPNs on a separate tab.

For an **IPsec** connection, you'll need these from your VPN admin:

- a name for the connection, such as Head Office. This is only for you.
- the gateway's address
- your VPN username
- the pre-shared key
- the internal networks or hosts you want to reach through the VPN
- the encryption proposals the gateway accepts, if they differ from the defaults

For an **SSL VPN** connection, you'll need:

- a name for the connection
- the gateway's address and port, such as `vpn.example.com` and `443`. Enter them in separate
  fields: `vpn.example.com:10443` becomes `vpn.example.com` and `10443`.
- your VPN username
- whether to save your password. See [SSL VPN connections](#ssl-vpn-connections).

 Change a connection with the edit button
in the app, or with `cygnet edit NAME`. Changes apply the next time you connect.

## Usage

### The app

Open **Cygnet** from your apps, pick a connection and enter your password. When the gateway asks
for your code, Cygnet asks for it too and sends a notification if its window isn't in front.

Closing the window leaves Cygnet running in the background, so it can tell you if the VPN drops.
Open Cygnet again to bring the window back, or use **Quit** in its menu to close it. Quitting
doesn't disconnect.

Cygnet doesn't ask for your admin password. This applies to admin users (members of `wheel` or
`sudo`) who are signed in at the computer. To be asked every time instead, delete
`/etc/polkit-1/rules.d/50-cygnet.rules`.

### The terminal

```sh
cygnet                     # connect, choosing a connection if you have several
cygnet connect "Head Office"
cygnet status              # show the tunnel
cygnet disconnect          # disconnect
cygnet list                # list your connections
cygnet add                 # add a connection
cygnet edit "Head Office"  # change a connection
cygnet remove "Head Office"
```

## SSL VPN connections

Cygnet runs openfortivpn as the `cygnet-ssl` service and answers its prompts itself. You still type
the password and code into Cygnet, never into openfortivpn.

**The gateway's certificate:** if your system doesn't trust it, Cygnet shows the certificate the
first time you connect and asks whether to trust it. This happens with self-signed certificates, and
when you connect by IP address to a gateway whose certificate names a hostname. If you trust it,
Cygnet remembers it and doesn't ask again. If the certificate changes later, such as when it's
renewed, Cygnet tells you it changed and asks again. If you can, check the SHA-256 fingerprint with
your VPN admin before trusting it. Changing the gateway or port forgets the trusted certificate.

**Saving the password:** this is off by default and set per connection. With it on, Cygnet stores
the password in `/opt/cygnet/etc/connections/<id>.password`, where only root can read it. When you
connect, it's sent for you and you're only asked for the code. If you turn saving on without
entering a password, you're asked for it on your next connection, and it's saved once the gateway
accepts it. If the gateway later rejects the saved password, Cygnet deletes it and asks you for it
the next time.

**Networks and DNS:** the gateway decides which networks go through the VPN, and which DNS servers to
use, as it does for FortiClient.

Have your inbox or phone ready before connecting, because the gateway limits how long you have to
enter the code. A dropped tunnel doesn't reconnect by itself, since that would need a new code.

If the gateway rejects a code, Cygnet signs in again with the password you already gave, so the
gateway sends a new code, and asks you for that one. It does this for 2 minutes after the first wrong
code; after that, you start again with your password. To stop sooner, press **Cancel** in the app or
Ctrl+C in the terminal. Each wrong code counts as a failed login, and too many can lock your account.

## Split or full tunnel

This applies to IPsec connections. For SSL VPN, the gateway decides.

A connection's networks decide what goes through the VPN.

**Split tunnel (recommended):** only what you list uses the VPN, and everything else uses your
normal connection. Single hosts are fine:

```
10.1.0.0/16, 10.2.3.4/32
```

**Full tunnel:** all IPv4 traffic uses the VPN:

```
0.0.0.0/0
```

A gateway can accept this and still not route internet traffic, which leaves connected machines
unable to reach IPv4 sites. IPv6 isn't carried by the tunnel in either mode, so with a full tunnel
IPv6 traffic still goes straight out over your normal connection.

**DNS:** servers handed out by the gateway are only used with a full tunnel. With a split tunnel your
system's DNS is left alone, so internal hostnames won't resolve unless you've set that up yourself.
Connecting by IP address always works.

## Troubleshooting

Logs are in `journalctl -u cygnet` for IPsec, and `journalctl -u cygnet-ssl` for SSL VPN. They don't
contain your password or code.

| Symptom | Likely cause |
|---|---|
| Connected, but an internal host doesn't respond | It's missing from the connection's networks, or the gateway's firewall doesn't allow it. In `cygnet status`, `out` above 0 with `in` at 0 means nothing is coming back. |
| `another program is using UDP ports 500 and 4500` | Another IPsec daemon is running, such as your distro's strongSwan or one left over from an older install. Only one can use those ports at a time. Stop the one the message names, then connect again. |
| The VPN drops after some hours, often 12, and the log says `CHILD_SA rekeying failed` | The gateway uses perfect forward secrecy, and the connection's ESP proposals don't name its key exchange group. Add the group to them, such as `aes256-sha256-modp2048`. The log line `received proposals: ESP:...` shows what the gateway wants. |
| `The gateway stopped answering` after you enter the code | You ran out of time. The gateway's `negotiate-timeout` defaults to 30 seconds, and an admin can raise it. |
| `rejected the final IKE authentication` | Try another `fortigate_auth_key` value in `strongswan-fortigate.conf`: `skp`, `msk` or `psk`. |
| `Stopped before sending a code` | The gateway didn't complete the password step as expected. See [Security](#security). |
| `didn't accept the encryption proposals` | The connection's IKE or ESP proposals don't match the gateway. |
| Other networks stop working once connected | One of the connection's networks overlaps your LAN or Docker networks. |
| SSL VPN: `The gateway rejected the code` | The code was wrong or expired. Cygnet signs in again for a new one, as it does for IPsec. |
| SSL VPN: `the gateway's certificate isn't trusted` | You declined the certificate. Connect again to be asked again. |
| SSL VPN: a sign-in that never asks for a code | The gateway may be sending a push notification to FortiToken Mobile. Approve it there. |

`strongswan-fortigate.conf` also has options that make the client identify itself to the gateway as
FortiClient. They're off by default. Some gateways may require them, but your organisation may not
allow them, so check first.

## How it works

```
cygnet                         charon (patched)               FortiGate
       |--- load password ------->|                               |
       |                          |---- PSK + MS-CHAPv2 --------->|
       |                          |<--- password OK --------------|
       |                          |     (sends you the code)      |
       |<-- otp-helper asks ------|<--- EAP-GTC: code please -----|
  you type the code               |                               |
       |--- code ---------------->|---- code -------------------->|
       |                          |<--- EAP-Success, tunnel up ---|
```

Once connected, the password is removed from the daemon's memory, as it's only needed to log in.

Each connection is stored in `/opt/cygnet/etc/connections`. `<id>.conf` holds its settings and
anyone on the computer can read it, so the app can list it. `<id>.psk` holds an IPsec connection's
pre-shared key, and `<id>.password` an SSL VPN connection's saved password. Only root can read
either. Only the IPsec connection you're using is loaded into the daemon.

For SSL VPN, cygnet writes openfortivpn's settings to `/run/cygnet-ssl`, without the password, and
starts `cygnet-ssl.service`. openfortivpn asks `ssl-pinentry` for the password and the code. That
helper tells cygnet what is needed and waits on a pipe for cygnet's answer, the same way
`otp-helper` does for IPsec.

The app runs `cygnet` through `pkexec` and talks to it over a pipe, so it never needs root itself.
It works out whether the VPN is up from the routes charon adds, which anyone can read.

## Security

- **Weak spot in this kind of VPN:** the pre-shared key is usually shared by all users, and it's what
  authenticates the gateway. Anyone who has it can pretend to be the gateway.
- **Added protection:** patch 07 sends your code only after the gateway has proven it knows your
  password, and only ever over EAP-GTC. Your password itself is only sent as an MS-CHAPv2 response,
  never as plain text.
- **Saved passwords:** a saved SSL VPN password is stored as plain text, readable only by root. Anyone
  with admin rights on the computer can read it. Leave saving off if that's a concern.
- **Trusting a certificate:** trusting the wrong certificate lets whoever holds it see your password.
  Your code still only works for one sign-in.
- **No admin password in the app:** any program running as an admin user can connect, disconnect
  and change Cygnet's connections without being asked. Connecting still needs your VPN password and
  code. Delete `/etc/polkit-1/rules.d/50-cygnet.rules` if you'd rather be asked.

## Trying the app without a VPN

`tests/fake-cygnet` stands in for the `cygnet` command, so you can try the app without a gateway or
root:

```sh
dir=$(mktemp -d)
CYGNET_CLI=tests/fake-cygnet CYGNET_CONN_DIR=$dir CYGNET_ACTIVE=$dir/active gui/cygnet-gui
```

## Uninstall

```sh
cygnet disconnect
sudo rm -rf /opt/cygnet /usr/local/bin/cygnet /usr/local/bin/cygnet-gui \
    /etc/systemd/system/cygnet.service /etc/systemd/system/cygnet-ssl.service \
    /usr/local/share/applications/io.github.Khalid_AlHajri.Cygnet.desktop \
    /usr/local/share/icons/hicolor/scalable/apps/io.github.Khalid_AlHajri.Cygnet.svg \
    /usr/share/polkit-1/actions/io.github.Khalid_AlHajri.Cygnet.policy \
    /etc/polkit-1/rules.d/50-cygnet.rules
sudo systemctl daemon-reload
```

## Credits and license

The FortiGate protocol work comes from the community. See [patches/README.md](patches/README.md) for
where each patch came from. strongSwan and the patches are GPL-2.0-or-later.
