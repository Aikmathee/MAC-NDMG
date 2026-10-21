"""Validated remote destinations; credentials are never persisted in URLs."""
import ctypes
from urllib.parse import urlsplit, urlunsplit, quote, unquote


def normalize_url(value):
    if not isinstance(value, str) or len(value) > 2048 or any(ord(c) < 32 for c in value):
        raise ValueError('Enter a valid drive URL.')
    parts = urlsplit(value.strip())
    if parts.scheme not in ('smb', 'https', 'http'):
        raise ValueError('Use smb:// for SMB or https:// for WebDAV. FTP/SFTP require a separate client.')
    if not parts.hostname or parts.username is not None or parts.password is not None or parts.query or parts.fragment:
        raise ValueError('Enter a server URL without a username, password, query or fragment.')
    host = parts.hostname.lower().rstrip('.')
    if any(c.isspace() for c in host) or any(c in host for c in '/\\'):
        raise ValueError('Enter a valid server hostname or IP address.')
    port = parts.port
    if port is not None and not 1 <= port <= 65535:
        raise ValueError('Enter a valid port.')
    if parts.scheme == 'smb' and port not in (None, 445):
        raise ValueError('Use the standard SMB port 445 through your VPN.')
    authority = f'[{host}]' if ':' in host else host
    if port is not None and port != {'https': 443, 'http': 80, 'smb': 445}[parts.scheme]:
        authority += f':{port}'
    path = quote(unquote(parts.path), safe='/!$&()*+,;=:@-._~').rstrip('/') or '/'
    if parts.scheme == 'smb' and path == '/':
        raise ValueError('Include the shared folder: smb://server/Share. For server browsing, enter only its hostname.')
    return urlunsplit((parts.scheme, authority, path, '', ''))


def mount_webdav(url):
    """Use macOS NetAuth for credentials/Keychain, never open HTTPS in a browser."""
    url = normalize_url(url)
    if urlsplit(url).scheme not in ('https', 'http'):
        raise ValueError('This is not a WebDAV URL.')
    cf = ctypes.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
    netfs = ctypes.CDLL('/System/Library/Frameworks/NetFS.framework/NetFS')
    ptr = ctypes.c_void_p
    cf.CFStringCreateWithCString.argtypes = [ptr, ctypes.c_char_p, ctypes.c_uint32]
    cf.CFStringCreateWithCString.restype = ptr
    cf.CFURLCreateWithString.argtypes = [ptr, ptr, ptr]
    cf.CFURLCreateWithString.restype = ptr
    cf.CFRelease.argtypes = [ptr]
    netfs.NetFSMountURLSync.argtypes = [ptr, ptr, ptr, ptr, ptr, ptr, ctypes.POINTER(ptr)]
    netfs.NetFSMountURLSync.restype = ctypes.c_int
    text = cf.CFStringCreateWithCString(None, url.encode('utf-8'), 0x08000100)
    target = cf.CFURLCreateWithString(None, text, None)
    mounts = ptr()
    try:
        status = netfs.NetFSMountURLSync(target, None, None, None, None, None, ctypes.byref(mounts))
        if status == -128:
            raise RuntimeError('Connection cancelled.')
        if status:
            raise RuntimeError(f'Could not connect to WebDAV (macOS {status}). Check VPN, address and server access.')
    finally:
        if mounts.value: cf.CFRelease(mounts)
        if target: cf.CFRelease(target)
        if text: cf.CFRelease(text)
