# syntax = docker/dockerfile:1.0-experimental

# name the portage image
FROM gentoo/portage:latest as portage

# image is based on stage3-amd64
FROM gentoo/stage3-amd64-hardened-nomultilib:latest as base

# copy the entire portage volume in
# COPY --from=portage /var/db/repos/gentoo /var/db/repos/gentoo

ENV FEATURES="-ipc-sandbox -mount-sandbox -network-sandbox -pid-sandbox -sandbox -usersandbox"

ADD portage/make.conf /etc/portage/make.conf
RUN --mount=type=bind,target=/var/db/repos/gentoo,source=/var/db/repos/gentoo,from=portage \
    --mount=type=cache,id=distfiles,target=/var/cache/distfiles \
    --mount=type=cache,id=binpkgs,target=/var/cache/binpkgs \
    emerge --buildpkg \
           --usepkg \
	   --binpkg-respect-use=y \
	   --binpkg-changed-deps=y \
	   --tree \
	   -vj \
	   -Du @world

ADD portage/* /etc/portage
ADD overlay /var/db/repos/local

FROM base as binpkgs 
RUN --mount=type=bind,target=/var/db/repos/gentoo,source=/var/db/repos/gentoo,from=portage \
    --mount=type=cache,id=distfiles,target=/var/cache/distfiles \
    --mount=type=cache,id=binpkgs,target=/var/cache/binpkgs \
    find /var/db/repos/local/ -iname '*.ebuild' -exec ebuild '{}' digest \; && \
    emerge --buildpkg \
           --usepkg \
	   --binpkg-respect-use=y \
	   --binpkg-changed-deps=y \
	   --tree \
	   -vj \
	   app-portage/gentoolkit net-fs/samba && \
    emerge --buildpkg -vt sys-process/runit && \
    ebuild /var/db/repos/gentoo/sys-process/runit/runit-2.1.2-r1.ebuild unpack && \
    equery f net-fs/samba
# net-dns/avahi

FROM base as runtime
RUN --mount=type=bind,target=/var/db/repos/gentoo,source=/var/db/repos/gentoo,from=portage \
    --mount=type=bind,target=/var/db/repos/local,source=/var/db/repos/local,from=binpkgs \
    --mount=type=cache,id=binpkgs,target=/var/cache/binpkgs \
    emerge --usepkgonly \
	   --binpkg-respect-use=y \
	   --binpkg-changed-deps=y \
	   --tree \
	   -vj \
	   sys-process/runit net-fs/samba && \
    rm -rfv /etc/service/* /var/lib/samba/private && \
    ln -Ts /config/samba/smb.conf /etc/samba/smb.conf && \
    ln -Tfs /config/samba/private/ /var/lib/samba/private

ADD bin/* /usr/local/bin/
ADD etc/* /etc/
STOPSIGNAL SIGINT
CMD /sbin/runit-init
