# syntax = docker/dockerfile:1.0-experimental

# name the portage image
FROM gentoo/portage:latest as portage

# image is based on stage3-amd64
FROM gentoo/stage3-amd64:latest

# copy the entire portage volume in
# COPY --from=portage /var/db/repos/gentoo /var/db/repos/gentoo

ENV FEATURES="-ipc-sandbox -mount-sandbox -network-sandbox -pid-sandbox -sandbox -usersandbox"

ADD bin/* /usr/local/bin/
ADD portage /build/etc/portage/
ADD overlay /var/db/repos/local

RUN --mount=type=bind,target=/var/db/repos/gentoo,source=/var/db/repos/gentoo,from=portage \
    --mount=type=cache,id=distfiles,target=/var/cache/distfiles \
    --mount=type=cache,id=binpkgs-build,target=/var/cache/binpkgs \
    --mount=type=cache,id=binpkgs-host,target=/var/cache/binpkgs \
    cd /var/db/repos/local/net-fs/samba/ && ebuild *.ebuild digest && \
    emerge-embedded --info && emerge-embedded -tv samba
#    emerge-embedded -tvj --buildpkg --usepkg \
#        avahi

# continue with image build ...
# RUN emerge -qv www-servers/apache
