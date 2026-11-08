# strongSwan patches

Applied in order to strongSwan 6.1.0 by `install.sh`.

- **01 to 06**: FortiGate compatibility, reverse-engineered by the community (see
  [strongSwan issue #3120](https://github.com/strongswan/strongswan/issues/3120)). Taken from
  [ebrjose/fortivpn-sgcan](https://github.com/ebrjose/fortivpn-sgcan), which derives them from
  [Noneawe/strongswan-deb-build](https://github.com/Noneawe/strongswan-deb-build) at commit
  `580192d321065a9628779ce77962cfd8851c2d73`. 05 and 06 do nothing unless enabled in
  `strongswan-fortigate.conf`.
- **07**: written for this project. Sends the OTP only after the gateway has proven it knows
  the password, and only ever continues into EAP-GTC.

strongSwan and these patches are GPL-2.0-or-later.
