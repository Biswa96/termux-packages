TERMUX_PKG_HOMEPAGE=https://pypy.org
TERMUX_PKG_DESCRIPTION="A fast, compliant alternative implementation of Python"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="@licy183"
_MAJOR_VERSION=2.7
TERMUX_PKG_VERSION="7.3.15"
TERMUX_PKG_SRCURL=https://downloads.python.org/pypy/pypy$_MAJOR_VERSION-v$TERMUX_PKG_VERSION-src.tar.bz2
TERMUX_PKG_SHA256=9e1a10d75eea8830f95035063e107bc7e4252a0b473407c929bf3d132ce6737f
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_DEPENDS="gdbm, libandroid-posix-semaphore, libandroid-support, libbz2, libcrypt, libexpat, libffi, liblzma, libsqlite, ncurses, ncurses-ui-libs, openssl, zlib"
TERMUX_PKG_BUILD_DEPENDS="binutils, clang, dash, make, ndk-multilib, pkg-config, python2, tk, xorgproto"
TERMUX_PKG_RECOMMENDS="clang, make, pkg-config"
TERMUX_PKG_SUGGESTS="pypy-tkinter"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_RM_AFTER_INSTALL="
opt/pypy/lib-python/${_MAJOR_VERSION}/test
opt/pypy/lib-python/${_MAJOR_VERSION}/*/test
opt/pypy/lib-python/${_MAJOR_VERSION}/*/tests
"

_docker_pull_url=https://raw.githubusercontent.com/NotGlop/docker-drag/5413165a2453aa0bc275d7dc14aeb64e814d5cc0/docker_pull.py
_docker_pull_checksums=04e52b70c862884e75874b2fd229083fdf09a4bac35fc16fd7a0874ba20bd075
_undocker_url=https://raw.githubusercontent.com/larsks/undocker/649f3fdeb0a9cf8aa794d90d6cc6a7c7698a25e6/undocker.py
_undocker_checksums=32bc122c53153abeb27491e6d45122eb8cef4f047522835bedf9b4b87877a907
_proot_url=https://github.com/proot-me/proot/releases/download/v5.3.0/proot-v5.3.0-x86_64-static
_proot_checksums=d1eb20cb201e6df08d707023efb000623ff7c10d6574839d7bb42d0adba6b4da
_qemu_aarch64_static_url=https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-aarch64-static
_qemu_aarch64_static_checksums=dce64b2dc6b005485c7aa735a7ea39cb0006bf7e5badc28b324b2cd0c73d883f
_qemu_arm_static_url=https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-arm-static
_qemu_arm_static_checksums=9f07762a3cd0f8a199cb5471a92402a4765f8e2fcb7fe91a87ee75da9616a806

# Skip due to we use proot to get dependencies
termux_step_get_dependencies() {
	echo "Skip due to we use proot to get dependencies"
}

termux_step_override_config_scripts() {
	:
}

termux_step_pre_configure() {
	if $TERMUX_ON_DEVICE_BUILD; then
		termux_error_exit "Package '$TERMUX_PKG_NAME' is not safe for on-device builds."
	fi

	local p="$TERMUX_PKG_BUILDER_DIR/9999-add-ANDROID_API_LEVEL-for-sysconfigdata.diff"
	echo "Applying $(basename "${p}")"
	sed 's|@TERMUX_PKG_API_LEVEL@|'"${TERMUX_PKG_API_LEVEL}"'|g' "${p}" \
		| patch --silent -p1

	DOCKER_PULL="python $TERMUX_PKG_CACHEDIR/docker_pull.py"
	UNDOCKER="python $TERMUX_PKG_CACHEDIR/undocker.py"
	PROOT="$TERMUX_PKG_CACHEDIR/proot"

	# Get docker_pull.py
	termux_download \
		$_docker_pull_url \
		$TERMUX_PKG_CACHEDIR/docker_pull.py \
		$_docker_pull_checksums

	# Get undocker.py
	termux_download \
		$_undocker_url \
		$TERMUX_PKG_CACHEDIR/undocker.py \
		$_undocker_checksums

	# Get proot
	termux_download \
		$_proot_url \
		$PROOT \
		$_proot_checksums

	chmod +x $PROOT

	# Get qemu-aarch64-static
	termux_download \
		$_qemu_aarch64_static_url \
		$TERMUX_PKG_CACHEDIR/qemu-aarch64-static \
		$_qemu_aarch64_static_checksums

	chmod +x $TERMUX_PKG_CACHEDIR/qemu-aarch64-static

	# Get qemu-arm-static
	termux_download \
		$_qemu_arm_static_url \
		$TERMUX_PKG_CACHEDIR/qemu-arm-static \
		$_qemu_arm_static_checksums

	chmod +x $TERMUX_PKG_CACHEDIR/qemu-arm-static

	# Pick up host platform arch.
	HOST_ARCH=$TERMUX_ARCH
	if [ $TERMUX_ARCH = "arm" ]; then
		HOST_ARCH="i686"
	elif [ $TERMUX_ARCH = "aarch64" ]; then
		HOST_ARCH="x86_64"
	fi

	# Get host platform rootfs tar if needed.
	if [ ! -f "$TERMUX_PKG_CACHEDIR/termux_termux-docker_$HOST_ARCH.tar" ]; then
		(
			cd $TERMUX_PKG_CACHEDIR
			$DOCKER_PULL ghcr.io/termux-user-repository/termux-docker:$HOST_ARCH
			mv termux-user-repository_termux-docker.tar termux_termux-docker_$HOST_ARCH.tar
		)
	fi

	# Get target platform rootfs tar if needed.
	if [ $HOST_ARCH != $TERMUX_ARCH ]; then
		# Check qemu version, must greater than 6.0.0, since qemu 4/5 cannot run python
		# inside the termux rootfs and will cause a segmentation fault, and qemu 6 hangs
		# on clang++
		QEMU_VERSION=$($TERMUX_PKG_CACHEDIR/qemu-$TERMUX_ARCH-static --version | grep "version" | sed -E "s/.*?version (.*?)/\1/g")
		QEMU_MAJOR_VERSION=${QEMU_VERSION%%.*}
		if [ $QEMU_MAJOR_VERSION -lt '7' ]; then
			termux_error_exit "qemu-user-static's version must be greater than 7.0.0"
		fi
		if [ ! -f "$TERMUX_PKG_CACHEDIR/termux_termux-docker_$TERMUX_ARCH.tar" ]; then
			(
				cd $TERMUX_PKG_CACHEDIR
				$DOCKER_PULL ghcr.io/termux-user-repository/termux-docker:$TERMUX_ARCH
				mv termux-user-repository_termux-docker.tar termux_termux-docker_$TERMUX_ARCH.tar
			)
		fi
	fi
}

termux_step_configure() {
	PYPY_USESSION_DIR=$TERMUX_ANDROID_HOME/tmp
	PYPY_SRC_DIR=$TERMUX_ANDROID_HOME/src

	# Bootstrap a proot rootfs for the host platform
	HOST_ROOTFS_BASE=$TERMUX_PKG_TMPDIR/host-rootfs
	cat "$TERMUX_PKG_CACHEDIR/termux_termux-docker_$HOST_ARCH.tar" | $UNDOCKER -o $HOST_ROOTFS_BASE

	# Add build dependicies for pypy on the host platform rootfs
	# Build essential
	BUILD_DEP="binutils binutils-gold clang file patch pkg-config "
	# Build dependencies for pypy
	BUILD_DEP+=${TERMUX_PKG_DEPENDS//,/}
	BUILD_DEP+=" "
	BUILD_DEP+=${TERMUX_PKG_BUILD_DEPENDS//,/}

	# Environment variables for termux
	TERMUX_RUNTIME_ENV_VARS="ANDROID_DATA=/data
			ANDROID_ROOT=/system
			HOME=$TERMUX_ANDROID_HOME
			LANG=en_US.UTF-8
			PATH=$TERMUX_PREFIX/bin:/usr/bin
			PREFIX=$TERMUX_PREFIX
			TMPDIR=$TERMUX_PREFIX/tmp
			TZ=UTC"
	ln -s $HOST_ROOTFS_BASE/$TERMUX_ANDROID_HOME/ $TERMUX_ANDROID_HOME
	ln -s $TERMUX_PKG_SRCDIR $PYPY_SRC_DIR
	PROOT_HOST="env -i PROOT_NO_SECCOMP=1
						$TERMUX_RUNTIME_ENV_VARS
						$PROOT
						-b /proc -b /dev -b /sys
						-b $HOME
						-b $TERMUX_ANDROID_HOME
						-w $TERMUX_ANDROID_HOME
						-r $HOST_ROOTFS_BASE/"
	# Get dependencies
	$PROOT_HOST update-static-dns
	sed -i "s/deb/deb [trusted=yes]/g" $HOST_ROOTFS_BASE/$TERMUX_PREFIX/etc/apt/sources.list
	$PROOT_HOST apt update
	$PROOT_HOST apt upgrade -yq -o Dpkg::Options::=--force-confnew
	sed -i "s/deb/deb [trusted=yes]/g" $HOST_ROOTFS_BASE/$TERMUX_PREFIX/etc/apt/sources.list
	$PROOT_HOST apt update
	$PROOT_HOST apt install -o Dpkg::Options::=--force-confnew -yq $BUILD_DEP
	$PROOT_HOST python2 -m pip install cffi pycparser

	# Copy the statically-built proot
	cp $PROOT $HOST_ROOTFS_BASE/$TERMUX_PREFIX/bin/

	# Extract the target platform rootfs to the host platform rootfs if needed.
	PROOT_TARGET="$PROOT_HOST"
	TARGET_ROOTFS_BASE=""
	if [ $HOST_ARCH != $TERMUX_ARCH ]; then
		TARGET_ROOTFS_BASE=$TERMUX_ANDROID_HOME/target-rootfs
		mkdir -p $HOST_ROOTFS_BASE/$TARGET_ROOTFS_BASE
		cat "$TERMUX_PKG_CACHEDIR/termux_termux-docker_$TERMUX_ARCH.tar" | $UNDOCKER -o $HOST_ROOTFS_BASE/$TARGET_ROOTFS_BASE
		PROOT_TARGET="env -i PROOT_NO_SECCOMP=1
			$TERMUX_RUNTIME_ENV_VARS
			$PROOT
			-q $TERMUX_PKG_CACHEDIR/qemu-$TERMUX_ARCH-static
			-b $HOME
			-b $TERMUX_ANDROID_HOME
			-b /proc -b /dev -b /sys
			-w $TERMUX_ANDROID_HOME
			-r $TARGET_ROOTFS_BASE"
		# Check if it can be run with or without $PROOT_HOST
		$PROOT_HOST $PROOT_TARGET uname -a
		$PROOT_TARGET uname -a
		# update-static-dns will use the arm busybox binary.
		${PROOT_TARGET/qemu-$TERMUX_ARCH-static/qemu-arm-static} update-static-dns
		# FIXME: If we don't add `[trusted=yes]`, apt-key will generate an error.
		# FIXME: The key(s) in the keyring XXX.gpg are ignored as the file is not readable by user '' executing apt-key.
		sed -i "s/deb/deb [trusted=yes]/g" $HOST_ROOTFS_BASE/$TARGET_ROOTFS_BASE/$TERMUX_PREFIX/etc/apt/sources.list
		$PROOT_TARGET apt update
		$PROOT_TARGET apt install -o Dpkg::Options::=--force-confnew -yq dash
		# Use dash to provide /system/bin/sh, since /system/bin/sh is a symbolic link
		# to /system/bin/busybox which is a 32-bit binary. If we are using an aarch64
		# qemu, proot cannot execute it.
		rm -f $HOST_ROOTFS_BASE/$TARGET_ROOTFS_BASE/system/bin/sh
		$PROOT_TARGET ln -sf $TERMUX_PREFIX/bin/dash /system/bin/sh
		# Get dependencies
		$PROOT_TARGET apt update
		$PROOT_TARGET apt upgrade -yq -o Dpkg::Options::=--force-confnew
		sed -i "s/deb/deb [trusted=yes]/g" $HOST_ROOTFS_BASE/$TARGET_ROOTFS_BASE/$TERMUX_PREFIX/etc/apt/sources.list
		$PROOT_TARGET apt update
		$PROOT_TARGET apt install -o Dpkg::Options::=--force-confnew -yq $BUILD_DEP
		# `pip2` is set up in the postinst script of `python2`, but it will segfault on aarch64. Install it manually.
		$PROOT_TARGET python2 -m ensurepip
		# Use the target rootfs providing $TERMUX_PREFIX
		if [ ! -L $TERMUX_PREFIX ]; then
			if [ -d $TERMUX_PREFIX.backup ]; then
				rm -rf $TERMUX_PREFIX.backup
			fi
			mv $TERMUX_PREFIX $TERMUX_PREFIX.backup
			ln -s $HOST_ROOTFS_BASE/$TARGET_ROOTFS_BASE/$TERMUX_PREFIX $TERMUX_PREFIX
		fi
		# Install cffi and pycparser
		$PROOT_TARGET python2 -m pip install cffi pycparser
	fi
}

termux_step_make() {
	mkdir -p $HOST_ROOTFS_BASE/$PYPY_USESSION_DIR

	# Translation
	$PROOT_HOST env -i \
			-C $PYPY_SRC_DIR/pypy/goal \
			$TERMUX_RUNTIME_ENV_VARS \
			PYPY_USESSION_DIR=$PYPY_USESSION_DIR \
			TARGET_ROOTFS_BASE=$TARGET_ROOTFS_BASE \
			PROOT_TARGET="$PROOT_TARGET" \
			$TERMUX_PREFIX/bin/python2 -u ../../rpython/bin/rpython \
					--platform=termux-$TERMUX_ARCH \
					--source --no-compile -Ojit \
					targetpypystandalone.py

	# Build
	cd $PYPY_USESSION_DIR
	cd $(ls -C | awk '{print $1}')/testing_1
	$PROOT_HOST env -C $(pwd) make clean
	$PROOT_HOST env -C $(pwd) make -j$TERMUX_PKG_MAKE_PROCESSES

	# Copy the built files
	cp ./pypy-c $PYPY_SRC_DIR/pypy/goal/pypy-c
	cp ./libpypy-c.so $PYPY_SRC_DIR/pypy/goal/libpypy-c.so

	# Build cffi imports
	TARGET_CFLAGS="-I$TERMUX_PREFIX/include -Wno-incompatible-function-pointer-types -Wno-implicit-function-declaration"
	TARGET_LDFLAGS="-L$TERMUX_PREFIX/lib -fno-termux-rpath -Wl,-rpath=$TERMUX_PREFIX/lib"
	$PROOT_TARGET env \
				TERMUX_STANDALONE_TOOLCHAIN=$TERMUX_STANDALONE_TOOLCHAIN \
				CFLAGS="$TARGET_CFLAGS" \
				LDFLAGS="$TARGET_LDFLAGS" \
				python2 $PYPY_SRC_DIR/pypy/tool/release/package.py \
					--archive-name=pypy$_MAJOR_VERSION-v$TERMUX_PKG_VERSION \
					--targetdir=$PYPY_SRC_DIR \
					--no-keep-debug
}

termux_step_make_install() {
	# Recover $TERMUX_PREFIX
	if [ $HOST_ARCH != $TERMUX_ARCH ]; then
		rm -rf $TERMUX_PREFIX
		mv $TERMUX_PREFIX.backup $TERMUX_PREFIX
	fi
	rm -rf $TERMUX_PREFIX/opt/pypy
	unzip -d $TERMUX_PREFIX/opt/ pypy$_MAJOR_VERSION-v$TERMUX_PKG_VERSION.zip
	mv $TERMUX_PREFIX/opt/pypy$_MAJOR_VERSION-v$TERMUX_PKG_VERSION $TERMUX_PREFIX/opt/pypy
	ln -sfr $TERMUX_PREFIX/opt/pypy/bin/pypy $TERMUX_PREFIX/bin/
	ln -sfr $TERMUX_PREFIX/opt/pypy/bin/libpypy-c.so $TERMUX_PREFIX/lib/
}

termux_step_create_debscripts() {
	# Pre-rm script to cleanup runtime-generated files.
	cat <<- PRERM_EOF > ./prerm
	#!$TERMUX_PREFIX/bin/sh

	if [ "$TERMUX_PACKAGE_FORMAT" != "pacman" ] && [ "\$1" != "remove" ]; then
	    exit 0
	fi

	echo "Deleting files from site-packages..."
	rm -Rf $TERMUX_PREFIX/opt/pypy/site-packages/*

	echo "Deleting *.pyc..."
	find $TERMUX_PREFIX/opt/pypy/lib-python/ | grep -E "(__pycache__|\.pyc|\.pyo$)" | xargs rm -rf
	find $TERMUX_PREFIX/opt/pypy/lib_pypy/ | grep -E "(__pycache__|\.pyc|\.pyo$)" | xargs rm -rf

	exit 0
	PRERM_EOF

	chmod 0755 prerm
}

termux_step_post_make_install() {
	rm -rf $TERMUX_ANDROID_HOME
}
