# syntax = docker/dockerfile:1.0-experimental

# name the portage image
FROM gentoo/portage:latest as portage

# base gentoo image
FROM gentoo/stage3-amd64-hardened-nomultilib:latest as base

# We can't use any sandboxing in the container.
ENV FEATURES="-ipc-sandbox -mount-sandbox -network-sandbox -pid-sandbox -sandbox -usersandbox"

# Add make.conf to override the march.
# This allows packages to be optimized specifically for the host CPU.
COPY base/pre-build/ /

# Update the base image
#
# The portage snapshot image is updated daily, while the base image
# is updated occasionally. We want to make sure we are always up to date.
#
# Other distros require the build cache to be manually invalidated to perform
# a system update. i.e., apt update. The reason being that the build cache can
# only hash the inputs. It doesn't realize that `apt update` performed an HTTP
# request to an external server, so it thinks it can reuse the same layer.
# Genoo doesn't suffer from this limitation. Since the portage database is
# provided as an image the build cache is properly invalidated when the portage
# database is updated.
# 
# In order to avoid rebuilding the same packages everytime there is a portage
# update, we generate bin packages and reuse the bin packages when regenerating
# the layer. It's questionable if using a bin package cache here is aceptable.
# The binpkgs don't take into account the CFLAGS, so the binpkgs won't be
# rebuilt when make.conf changes. If a rebuild is required, the bin package
# cache can be wiped.
#
# Additionally the distfiles are cached to avoid constantly downloading the
# package source on every rebuild. This is safe since each tarball is versioned
# and `should` never change.
RUN --mount=type=bind,target=/var/db/repos/gentoo,source=/var/db/repos/gentoo,from=portage \
    --mount=type=cache,id=distfiles,target=/var/cache/distfiles \
    --mount=type=cache,id=base-binpkgs,target=/var/cache/binpkgs \
    emerge --buildpkg \
           --usepkg \
	   --binpkg-respect-use=y \
	   --binpkg-changed-deps=y \
	   --tree \
	   -vj \
	   -Du @world

# Portage packages define build time and runtime dependencies. We don't want
# any of the build time dependencies in the final image. So we split the image
# creation into two steps.
# 1) emerge the app and generate bin packages for all dependencies. This has
#    the advantage that we can also reuse the bin packages when regenerating
#    this layer.
# 2) emerge the app using only bin packages. This allows us to drop all the
#    build time dependencies and only install the runtime dependencies.
# 
# TODO: It would be nice to generate the final image with only the runtime
# deps requires to run the app. i.e., emerge --destination /image <package>
# Then we don't need the gentoo base package at all at runtime, but this
# requires packages to migrate to EAPI 7 and correctly define their BDEPENDs.
FROM base as binpkgs 

# Create a local overlay so we can provide our own ebuilds.
COPY binpkgs/pre-build/ /

# We use runit as our supervisor
FROM binpkgs as runit-binpkgs
COPY runit/pre-build/ /
# We don't reuse the runit binpkg we generate because we apply a custom patch.
# Portage doesn't take that into account when deciding to use the binpkg. If
# the patch is updated, then we end up with a stale binpkg installed.
RUN --mount=type=bind,target=/var/db/repos/gentoo,source=/var/db/repos/gentoo,from=portage \
    --mount=type=cache,id=distfiles,target=/var/cache/distfiles \
    digest-local && \
    emerge --buildpkg -vt @runit

FROM base as runit
RUN --mount=type=bind,target=/var/db/repos/gentoo,source=/var/db/repos/gentoo,from=portage \
    --mount=type=bind,target=/var/db/repos/local,source=/var/db/repos/local,from=runit-binpkgs \
    --mount=type=bind,target=/etc/portage,source=/etc/portage,from=runit-binpkgs \
    --mount=type=bind,target=/var/cache/binpkgs,source=/var/cache/binpkgs,from=runit-binpkgs \
    emerge --usepkgonly \
	   --binpkg-respect-use=y \
	   --binpkg-changed-deps=y \
	   --tree \
	   -vj \
	   @runit && \
    rm -rfv /etc/runit/* /etc/service/*
COPY runit/post-install/ /
STOPSIGNAL SIGINT
CMD ["/sbin/runit-init"]
HEALTHCHECK --interval=10s CMD ["/usr/local/sbin/runit-check"]

FROM binpkgs as samba-binpkgs
COPY samba/pre-build/ /
RUN --mount=type=bind,target=/var/db/repos/gentoo,source=/var/db/repos/gentoo,from=portage \
    --mount=type=cache,id=distfiles,target=/var/cache/distfiles \
    --mount=type=cache,id=samba-binpkgs,target=/var/cache/binpkgs \
    digest-local && \
    emerge --buildpkg \
           --usepkg \
	   --binpkg-respect-use=y \
	   --binpkg-changed-deps=y \
	   --tree \
	   -vj \
	   @samba

FROM runit as samba
RUN --mount=type=bind,target=/var/db/repos/gentoo,source=/var/db/repos/gentoo,from=portage \
    --mount=type=bind,target=/var/db/repos/local,source=/var/db/repos/local,from=samba-binpkgs \
    --mount=type=bind,target=/etc/portage,source=/etc/portage,from=samba-binpkgs \
    --mount=type=cache,id=samba-binpkgs,target=/var/cache/binpkgs \
    emerge --usepkgonly \
	   --binpkg-respect-use=y \
	   --binpkg-changed-deps=y \
	   --tree \
	   -vj \
	   @samba && \
    rm -r /var/lib/samba/private && \
    ln -Ts /config/samba/smb.conf /etc/samba/smb.conf && \
    ln -Tfs /config/samba/private/ /var/lib/samba/private
COPY samba/post-install/ /
COPY util/passwd/post-install/ /
VOLUME /config
