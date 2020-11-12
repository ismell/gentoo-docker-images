# Gentoo Docker Containers

A collection of containers built using the official
[Gentoo Docker Images](https://github.com/gentoo/gentoo-docker-images).

## Gentoo Samba

### Features

* Direct access to `smb.conf` - Samba has too many configuration options to
  pass via environment variables, so it's best to manually modify it to fit
  the use case. `smb.conf` is located in the `/config` data volume at
  `/config/samba/smb.conf`. It can be modified using either `vi` or `nano` from
  inside the container, or the `config` share via your favorite editor.
* Auto reload on `smb.conf` change - The `samba-config` service will monitor
  `smb.conf` for changes and automatically reload `smbd`.
* Persistent users and groups - System users and groups can be added using the
  standard `useradd` and `groupadd`, modified using `usermod` and `groupmod`,
  and deleted using `userdel` and `groupdel`. The modifications will be stored
  in the `/config` data volume at `/config/passwd` and `/config/groups`. If 
  you need to manually modify one of these files while your container is
  running use `vipw` (vi passwd) or `vigr` (vi group). It will make sure the
  changes get correctly applied to the container and `/config` volume.
  * Persistent home directories - Home directories are created in the `/data`
    volume at `/data/home/<user>`. The `Homes` share is enabled by default.
  * `add user script` - The default `smb.conf` has the `add user script`
    configured to automatically create a system user. This means you can use
    `smbpasswd -a <user>` to add a new samba user an it will automatically
    create a system user.
* Modern discovery protocols - NetBIOS has been deprecated and is no longer
  enabled by default on new Windows 10 installs.
  * Avahi - Provides auto discovery and name resolution for OS X and mDNS
    clients. The container will appear in the OS X network browser and be
    resolvable using `<hostname>.local`.
  * [WSDD](https://github.com/christgau/wsdd) - Web Service Discovery provides
    auto discovery to Windows clients and allows the samba server to be listed
    in the network browser. This is the replacement for NetBIOS.
* OS X support - In order to get proper OS X support, the `fruit` vfs
  object needs to be enabled and configured. The default `smb.conf` correctly
  configures `vfs_fruit` for linux.
  * Time Machine support - The default `smb.conf` has support for Time Machine.
    Users don't have to do anything special. The backups will be stored in the
    users `$HOME`.
  * xattr verification - `vfs_fruit` and Time Machine require xattr support
    from the underlying filesystem. By default `ext4` does not have `xattr`
    support enabled without adding the `user_xattr` flag. On container startup
    a warning will be printed if any shares don't have support for `xattr`s
    enabled. Additionally the Time Machine share will refuse to work and print
    an error in the console if `xattrs` are not enabled. This prevents hard to
    diagnose errors while performing a backup.
* Logging controls - Set `DEBUG=1` to enable verbose logging to debug the
  container.

### Notes
* [NTFS Alternate Data Streams](https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-fscc/b134f29a-6278-4f3f-904f-5e58a713d2c5)
  are implemented using using the [streams_xattr](https://www.samba.org/samba/docs/current/man-html/vfs_streams_xattr.8.html)
  vfs object. `ext4` has a very small (1 KiB - 4 KiB) limit for xattrs, so
  this may cause compatability problems with applications that use ADS. See
  [man xattr](https://man7.org/linux/man-pages/man7/xattr.7.html) for
  specifics. `XFS`,
  `ZFS`, and `ReiserFS` don't have this limit. It is recommended to use one
  of those filesystems for the best compatability. The linux VFS still
  imposes a 64 KiB limit though.
* Multicast discovery will only work if the container is joined directly to
  your LAN. It won't function through the bridge network. You will need to
  create a [macvlan](https://docs.docker.com/network/macvlan/) network.

  i.e.,
  ```
  docker network create -d macvlan \
    --subnet=192.168.32.0/24 \
    --ip-range=192.168.32.128/25 \
    --gateway=192.168.32.1 \
    -o parent=eth0 lan
  ```

### Usage

```sh
docker run -it --rm 
   --network lan \
   --name grizmos \
   --hostname grizmos \
   --mount source=grizmos-config,target=/config \
   --mount source=grizmos-data,target=/data \
   ismell/gentoo-samba:latest
```

You will now have a samba server running on your LAN named `grizmos`. It will
show up in the OS X network browser and the Windows 10 network browser.

#### Config Modification
In order to modify `smb.conf`, you have two options:
1. Add a password for the root user and edit `smb.conf` via the `config` share.

  ```sh
  docker exec -it "$(docker ps -f name=grizmos -q)" smbpasswd -a root
  ```

  Now use your favorite editor to navigate to `\\grizmos\config\samba\smb.conf`

2. Directly using `vi` or `nano`
  ```sh
  docker exec -it "$(docker ps -f name=grizmos -q)" vi /config/samba/smb.conf
  ```
In both cases if you look at the logs, you will notice the `samba-config`
service will reload `smbd` when `smb.conf` is modified.

#### User Management

Local users are managed using the standard tools.

Adding a local user and setting a samba password can be accomplished with a
single command:

```sh
docker exec -it "$(docker ps -f name=grizmos -q)" smbpasswd -a cumulo
```

This user will have a home directory created at `/data/home/cumulo` and can be
accessed via `\\grizmos\cumulo`. Time Machine backups will also be stored in
`/data/home/cumulo/TimeMachineBackup`.

If you need to add a user with a specific `UID` you can do the following:

```sh
docker exec -it "$(docker ps -f name=grizmos -q)" useradd -u 1234 bartleby
docker exec -it "$(docker ps -f name=grizmos -q)" smbpasswd -a bartleby
```
