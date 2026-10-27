# MacNDMG

A native macOS app for finding servers and connecting to multiple SMB shared
drives. SwiftUI and AppKit provide the interface; the bundled Python service
handles discovery, authentication, mounting, and saved servers.

## Use the app

Requires **macOS 13 or newer**. The distributed app includes Python.

1. Unzip `Network-Drive-Manager-macOS.zip` and move the app into Applications.
2. The app opens to **Overview**, shows connected drives, and searches automatically. Servers already mounted by Finder are included even without a Bonjour advertisement.
3. Choose a server and choose **Load drives**. Existing Finder SMB sessions are tried first.
4. Select the drives you want and choose **Connect**.
5. Connected drives offer **Open**; select them and choose **Eject** to disconnect.

**Connected** in the sidebar lists network drives already mounted on this Mac,
including connections made in Finder before opening the app. Each row shows the
server and actual mount location, with **Open** and **Eject** actions. Overview
shows a short preview with **View all**. The list refreshes every three seconds,
when the app becomes active, and after an operation. Eject uses normal macOS
unmounting; if a drive is busy, its error is shown and the app does not force it.
Local disks are not included. Duplicate drive names and multiple mounts of the
same share are tracked separately by their real mounted source and path.

### Multiple selection and batch actions

The server sidebar, Connected list, shared-drive list, and Groups & saved drives
use native macOS selection. **Command-click** adds/removes an item;
**Shift-click** selects a range; **Command-A** selects all in the focused list.
**Control-click** or right-click opens actions for the clicked selection.

- Select multiple servers, then choose **Connect all** or **Eject all**.
- **Connected** offers **Eject selected** and **Eject all**.
- Groups offer **Connect group** and **Eject group**; multiple groups and saved
  drives can be selected together, with overlapping destinations handled once.
- **Save selection as group** creates a reusable set from the current selection.
- Batch eject continues past busy drives, reports failures, and never forces an unmount.

### Hostnames and changing LAN addresses

Discovered servers use their advertised Bonjour/DNS hostname (for example,
`editing-mac.local`) as the SMB destination and saved identity. The current IP
is discovery metadata, not a permanent destination. macOS resolves the hostname
again when connecting, so DHCP changes do not require editing a hostname-based
server or group. Explicit DNS and VPN/MagicDNS names are preserved as entered.
If discovery supplies only an IP, the app keeps that IP; it never invents a
hostname from a display name or silently falls back to yesterday's IP.

Existing Finder connections keep their original endpoint until you eject and
reconnect them. Old saved servers/groups recorded only by IP are not silently
migrated: a reused IP could now identify another computer. Connect the server by
its hostname, then save that destination and update the group's members once.
Devices without working Bonjour/DNS still need a valid IP or a configured DNS
name. `.local` discovery usually requires the same LAN; across a VPN, use its
working DNS name rather than assuming multicast Bonjour is forwarded.

### Remembered accounts

**Load drives** and **Connect all** first try an existing SMB session managed by
macOS. No password is extracted from Finder or copied into app storage. If a
sign-in sheet is needed, choose **Use Finder** to open macOS sign-in, then return
and choose **Sign in**. macOS may reuse a saved account or ask you to authenticate;
reuse depends on the server address, account, session and Keychain access.

You can also enter an account in the app. **Remember account** stores that
validated account in the app's own Keychain namespace, only after shares can be
listed. **Forget saved account** removes that app account, not Finder's account.
Passwords never go into server/group JSON files. Changing a hostname or IP may
require sign-in again. Saved-drive reconnects without an app account already use
Finder's normal sign-in flow.

### Safe eject

Eject always uses normal macOS unmounting. Ejecting multiple drives asks for
confirmation; busy drives remain connected while the batch continues. If an
eject fails, a sheet shows the drive, a short cause, and detected app/process
names with PIDs. **Details** contains the macOS message. Close open files and
choose **Retry**, or open **Activity Monitor** to inspect the named process.

Process lookup uses a bounded, nonrecursive `lsof` filesystem query. It does not
request administrator access, read file contents, or collect filenames/arguments.
macOS may hide other users' or system processes; an empty result is not proof
that no app is using the drive. The app never force-unmounts or closes apps.

### Help

The **?** toolbar button contains selection shortcuts, account behavior, groups,
VPN guidance and eject help. The **?** button in Add server explains address
formats. Longer instructions are kept out of the main pages.

### Saved drives and groups

Open **Groups** in the sidebar to reconnect previously used SMB drives. The app
remembers destinations from its live connected-drive inventory, including Finder
connections. Its JSON file stores server/share names, never usernames or passwords; optional accounts live separately in Keychain.

1. Choose **New group**, give it a name, and check the drives to include.
2. Choose **Save group**. Drives may come from different servers.
3. Choose **Connect group** when you want the set connected.

Group cards show connection status and server count, with Eject and Connect
beside each other. Click the drive count to expand or collapse all members,
arranged by server. Cards start collapsed to keep the list compact.

Use the group's options menu to edit its name/members or delete the group.
Deleting a group does not eject its drives. **Select connected** in the editor
selects the SMB drives currently connected to the Mac.

Groups connect only when you click Connect. Already mounted destinations are
skipped, and duplicate mounts of the same share are remembered once. Finder
uses its normal authentication flow and may ask for credentials. A request
waiting for Finder is shown as waiting, not as successfully connected. **Stop**
in the status bar stops the remaining queue after the current request finishes.

Saved drive and group data is stored in
`~/Library/Application Support/MAC-NDMG/connections.json`. Concurrent updates are
locked and written atomically. The app does not schedule automatic connections.

**Add server** accepts an IP address or hostname. **Save** keeps the current
server and drive names for next time. **Use Finder** opens the macOS connection
flow and lets Finder manage authentication. **Activity** shows recent results.

- `⌘R`: refresh discovery from Overview.
- `⌘K`: add a server.
- Choose **Appearance → Dark**, **Light**, or **System** at the bottom of the sidebar.
  The app remembers your choice across launches and applies it to sheets and glass surfaces.
- macOS 26 uses the system's `NSGlassEffectView` for Liquid Glass surfaces.
  Earlier macOS versions use `NSVisualEffectView` materials.
- Preferences live in `~/Library/Application Support/MAC-NDMG/shares.json`.
- Accounts stay in memory for the app session unless Remember is selected; remembered accounts live in Keychain.
  Existing SMB system commands receive credentials as arguments, which may be
  visible to local process inspection. Use Finder for OS-managed authentication.
- No localhost web server or port 8888 is needed. SMB uses the server's port 445.
- Recipients must be on the server's network or a suitable VPN.

The locally built app is ad-hoc signed, not Apple-notarized. A warning-free first launch
requires an Apple Developer signing identity and notarization. Build on the CPU
architecture you want to support; choose the Apple Silicon or Intel download for your Mac.

Build instructions and project layout: [Development guide](DEVELOPMENT.md).

## Remote drives: Tailscale, VPN and WebDAV

Use **Add server** with a hostname or IP to browse SMB shares, including a Tailscale `100.x.y.z` address or MagicDNS hostname. Connect your VPN first; LAN scans do not discover remote machines. The VPN must provide a route to the server and permit SMB access. The app does not install or manage VPN connections.

To save a particular drive directly, enter a URL:

- `smb://nas.example.ts.net/Projects` — SMB over Tailscale or another VPN (standard port 445).
- `https://cloud.example.com:8443/remote.php/dav/files/account/` — an actual WebDAV endpoint, such as the URL supplied by your NAS or Nextcloud. An ordinary website URL is not a WebDAV drive.
- `http://server/dav/` — WebDAV over a trusted VPN; use HTTPS for Internet access.

Saved destinations appear in **Groups** alongside previously connected drives, can be selected together, and support existing Connect and Eject group actions. Saving a URL does not initiate a connection. WebDAV uses macOS NetFS and its system sign-in window, including system Keychain handling. Embedded passwords, query strings and fragments are rejected and never saved. SMB continues to use the app's saved account when available. Live WebDAV matching preserves protocol, port and case-sensitive path; successful opening alone is never reported as a verified connection.

DNS supplies an address, not a file-sharing service. Use SMB over a VPN rather than exposing port 445 publicly. FTP, FTPS and SFTP are not currently mounted by this app; use a dedicated client or expose a supported SMB/WebDAV service through your VPN. No VPN subscription or server setup is included in the app.

References: [Tailscale remote file servers](https://tailscale.com/docs/use-cases/personal-or-at-home-use/access-nas-media-file-servers), [MagicDNS](https://tailscale.com/docs/features/magicdns), [Apple WebDAV connections](https://support.apple.com/en-hk/guide/mac-help/mchlp1546/mac).

## Drives moved between servers

Connecting a group now lists drives that did not connect, including requests still waiting in Finder. A disconnected disk may be unplugged, offline, require sign-in, or have moved. Other successfully connected drives stay connected.

Choose **Find in LAN**, or **Find** beside a disconnected saved drive in Groups. Search checks discovered SMB servers using existing macOS sessions and lists exact share-name matches. It does not send an old server's saved password to other servers. A server requiring sign-in may be missing from results: sign in through Finder and search again.

Check that the candidate really is your disk, then choose **Use this location**. The saved location is updated, the old address is retained in local history, and group memberships are preserved. Connect again from Groups. Multiple matches are never chosen automatically. SMB share names do not provide a universal physical disk identifier, so the app cannot guarantee identity or find unplugged disks, renamed shares, undiscoverable servers, or shares you cannot access.

Servers used by saved SMB drives remain visible after disconnecting, even when LAN discovery cannot find them. A saved server is not proof that it is online; connecting still requires its hostname to resolve and SMB to be available.

Discovery also reads NetBIOS server names from SMB hosts. This covers machines Finder can show even when they do not advertise Bonjour and have no DNS record. Short NetBIOS names are resolved on the current network; the app does not pin their old IP addresses. Networks that block NetBIOS may require Bonjour, DNS, or manually adding an address.

## Slow or disconnected networks

Connection-service requests have time limits: 45 seconds for regular operations, 90 seconds for discovery and 180 seconds for finding a moved share. If a request times out, check the network or VPN and try again. A timeout does not guarantee macOS cancelled a mount or unmount; check the Connected page, which refreshes from the actual mount table. MacNDMG does not force an unmount or quit other apps.

Stopping a group shows both unresolved and unattempted drives. Successfully connected drives stay connected.

## Update reminders

Open **Updates** using the down-arrow-circle button in the toolbar. Choose **Every day** (default), **Every 2 days**, or **Off**. Checks happen while MacNDMG is open, with the schedule retained across restarts. **Check now** is available even when automatic checks are off.

A newer complete stable GitHub Release shows an in-app banner. **Downloads** opens that release's page containing installers; **Later** dismisses the banner until a future scheduled reminder. You download and install the app yourself. The app does not automatically download or install updates, request macOS notification permission, or run an updater while closed.

Checks use the public GitHub API without GitHub login or transmitting saved servers, accounts or passwords. Internet failure is quiet and rate-limited checks wait until the next scheduled attempt. Code pushes alone do not trigger notifications; the release must have all installer files published.

## Preview releases and support

The public preview series starts at **Preview 1**. A separate increasing internal version keeps update ordering compatible with previous builds. Find both under **About & support → About MacNDMG** at the bottom of the sidebar.

The same menu contains **Updates**, **Contact me** (Instagram), **Report a bug** (GitHub Issues) and **Buy me a coffee**. These open external pages; nothing is posted or paid automatically. Remove private server/account information from public bug reports.
