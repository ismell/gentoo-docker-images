# Copyright 2020 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7
PYTHON_COMPAT=( python3_{7,8} )
PYTHON_REQ_USE="xml(+)"

inherit python-r1 systemd

DESCRIPTION="A Web Service Discovery host daemon."
HOMEPAGE="https://github.com/christgau/wsdd"
SRC_URI="https://github.com/christgau/wsdd/archive/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
SLOT="0"
KEYWORDS="amd64 ~arm ~x86"
IUSE="samba"
REQUIRED_USE="${PYTHON_REQUIRED_USE}"

DEPEND="${PYTHON_DEPS}"
# Samba is technically no requiredment of wsdd, but depend on it if the use flags is set.
RDEPEND="${DEPEND} samba? ( net-fs/samba )"
BDEPEND=""

src_install() {
	python_foreach_impl python_newscript src/wsdd.py wsdd

	# remove dependency on samba from init.d script if samba is not in use flags
	if ! use samba ; then
		sed -i -e '/need samba/d' etc/openrc/init.d/wsdd
	fi

	doinitd etc/openrc/init.d/wsdd
	doconfd etc/openrc/conf.d/wsdd

	# install systemd unit file with wsdd user and dependency on samba service if use flag is set
	sed -i -e 's/=nobody/=daemon/' etc/systemd/wsdd.service
	if use samba; then
		sed -i -e 's/;Wants=smb.service/Wants=samba.service/' etc/systemd/wsdd.service
	fi
	systemd_dounit etc/systemd/wsdd.service

	dodoc README.md
	doman man/wsdd.1
}
