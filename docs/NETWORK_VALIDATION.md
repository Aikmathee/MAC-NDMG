# Network validation record

This is a coverage record, not a claim that all networks have been tested.

| Scenario | Evidence available | Still needed |
| --- | --- | --- |
| DNS / NetBIOS address changes | Automated regressions; earlier read-only LAN discovery | DHCP change on a dedicated test network |
| Finder session reuse | Earlier read-only real share enumeration | Multiple macOS accounts / servers and expired sessions |
| Group partly unavailable / stopped | Automated regressions and earlier synthetic UI checks | Disconnect a noncritical test disk and reconnect it |
| Same share moved / duplicate names | Automated relocation and ambiguity regressions | Physical test disk move between two test servers |
| Service stalls / incomplete responses | Swift subprocess tests in CI, both architectures | Extended sleep/wake and network-loss soak test |
| Eject failure / applications using drive | Automated and earlier synthetic UI checks | Noncritical disk with a deliberately open test file |
| SMB over VPN / Tailscale | Endpoint handling; no end-to-end external-network result | Dedicated remote server, VPN reconnect and authentication |
| WebDAV | URL and bridge checks | Real HTTPS WebDAV server with valid certificate |
| Developer ID / notarization | Preflight and mocked signing/submission tests | Actual certificate, Apple acceptance, clean-Mac launch |

Do not unplug production drives, turn off the user's network, change DHCP, expire user credentials or eject active working volumes as a test. Use a separate test network and disposable share. Record OS versions, architecture, protocol and pass/fail without publishing studio hostnames, IPs, usernames, credentials or screenshots containing them.
