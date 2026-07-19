# FTP Mount

FTP Mount is a native macOS app that mounts FTP, SFTP, and WebDAV servers as Finder drives.

## What works

- Create, edit, save, and delete FTP, SFTP, and WebDAV bookmarks.
- Save server, optional port, username, optional root directory, and display name.
- Store passwords in the encrypted macOS login Keychain.
- Verify SFTP server keys against `~/.ssh/known_hosts` by default.
- Mount an FTP, SFTP, or WebDAV location as a read/write Finder volume.
- Reveal a mounted volume in Finder and unmount it from the app.
- Supervise the mount process and report startup/runtime failures.
- Works on Apple Silicon and Intel Macs.

## Install FTP Mount

1. Download the `FTP Mount.app` distribution.
2. Drag **FTP Mount** to your **Applications** folder.
3. Open it. If macOS prevents it from opening, use Control-click → **Open**, then confirm.

## Set up mounting support

Open **FTP Mount → Settings** and complete the two setup items:

1. **rclone** — click **Install rclone**. FTP Mount downloads the official rclone binary and installs it for your user account. 
2. **macFUSE** — click **Download macFUSE** to open the official macFUSE site. Download and run its installer, then return to FTP Mount and click **Check Again**. macOS may ask for an administrator password and approval in **System Settings → Privacy & Security**. Restart if macOS asks you to.

Once macFUSE is installed, use **Activate macFUSE** in Settings if it is shown. Approve any macOS prompt, then check again.

## Connect a server

1. Click **Add Bookmark**.
2. Choose FTP, SFTP, or WebDAV and enter the server details.
3. Click **Mount**. The connection appears in Finder as a drive.
4. Keep FTP Mount open while the drive is mounted. Use **Unmount** in the app when you are finished.

For WebDAV, enter the complete WebDAV URL, for example:

```text
https://cloud.example.com/remote.php/dav/files/name/
```

Choose the matching server type for Nextcloud, ownCloud, Fastmail, or SharePoint; choose **Other** for standard WebDAV servers.

## Storage and security

Connection details are stored at:

```text
~/Library/Application Support/FTP Mount/bookmarks.json
```

Passwords are stored separately in your macOS login Keychain. They are not stored in the bookmark file or synced by FTP Mount.

## Troubleshooting

- **A setup item is not ready:** Open **Settings**, complete the action shown, then click **Check Again**.
- **macFUSE is installed but inactive:** Choose **Activate macFUSE**, approve any macOS security request, and restart if requested.
- **The drive does not appear in Finder:** Confirm that macFUSE is active, then unmount and mount the bookmark again.
- **SFTP connection is rejected:** Trust the server key first by connecting once in Terminal with `ssh username@server`, verify the displayed fingerprint with the server administrator, and accept it. FTP Mount checks `~/.ssh/known_hosts` by default.

## Security notes

- Prefer SFTP or HTTPS WebDAV. Plain FTP does not encrypt usernames, passwords, or transferred data.

- FTP Mount verifies SFTP server identities against `~/.ssh/known_hosts` by default. Do not disable this unless you understand the security risk.

- The temporary rclone configuration used for a mount is removed after the mount ends.
