#!/bin/bash

export LC_ALL=C
DIR=$PWD
git_bin=$(which git)

BUILD="5.10.61"

mkdir -p "${DIR}/deploy/"

/bin/sh -e "${DIR}/gcc.sh" || { exit 1 ; }
. "${DIR}/.CC"
. "${DIR}/version.sh"
echo "CROSS_COMPILE=${CC}"

if [ ! "${CORES}" ] ; then
	CORES=$(($(getconf _NPROCESSORS_ONLN) * 2)) # cores and thread
fi

#/bin/sh -e "${DIR}/build-uboot.sh" || { exit 1 ; }


copy_defconfig () {
	cd "${DIR}/linux" || exit
	#make ARCH=${KERNEL_ARCH} CROSS_COMPILE="${CC}" distclean
	#make ARCH=${KERNEL_ARCH} CROSS_COMPILE="${CC}" "${config}"
	cp -v "${DIR}/defconfig_${config}" .config
	cd "${DIR}/" || exit
}

make_menuconfig () {
	cd "${DIR}/linux" || exit
	#make ARCH=${KERNEL_ARCH} CROSS_COMPILE="${CC}" oldconfig
	make ARCH=${KERNEL_ARCH} CROSS_COMPILE="${CC}" menuconfig
	cp -v .config "${DIR}/defconfig_${config}"

	cd "${DIR}/" || exit
}

make_kernel () {
    image="zImage"

    cd "${DIR}/linux" || exit
	echo "-----------------------------"
	echo "make -j${CORES} ARCH=${KERNEL_ARCH} CROSS_COMPILE=\"${CC}\" ${image} modules"
	echo "-----------------------------"
	make -j${CORES} ARCH=${KERNEL_ARCH} CROSS_COMPILE="${CC}" ${image} modules
	echo "-----------------------------"
	echo "make -j${CORES} ARCH=${KERNEL_ARCH} CROSS_COMPILE=\"${CC}\" dtbs"
	echo "-----------------------------"
	make -j${CORES} ARCH=${KERNEL_ARCH} CROSS_COMPILE="${CC}" dtbs
	echo "-----------------------------"

	KERNEL_UTS=$(cat "${DIR}/linux/include/generated/utsrelease.h" | awk '{print $3}' | sed 's/\"//g' )

    echo "${KERNEL_UTS}"

    if [ -f "${DIR}/deploy/${KERNEL_UTS}.${image}" ] ; then
		rm -rf "${DIR}/deploy/${KERNEL_UTS}.${image}" || true
		rm -rf "${DIR}/deploy/config-${KERNEL_UTS}" || true
	fi

	if [ -f ./arch/${KERNEL_ARCH}/boot/${image} ] ; then
		cp -v arch/${KERNEL_ARCH}/boot/${image} "${DIR}/deploy/${KERNEL_UTS}.${image}"
        cp -v arch/${KERNEL_ARCH}/boot/${image} "${DIR}/deploy/${image}"
		cp -v .config "${DIR}/deploy/config-${KERNEL_UTS}"
	fi

	cd "${DIR}/" || exit

	if [ ! -f "${DIR}/deploy/${KERNEL_UTS}.${image}" ] ; then
		export ERROR_MSG="File Generation Failure: [${KERNEL_UTS}.${image}]"
		/bin/sh -e "${DIR}/scripts/error.sh" && { exit 1 ; }
	else
		ls -lh "${DIR}/deploy/${KERNEL_UTS}.${image}"
        ls -lh "${DIR}/deploy/${image}"
	fi

}

make_pkg () {
	cd "${DIR}/linux" || exit
    #KERNEL_UTS=${BUILD}

	deployfile="-${pkg}.tar.gz"
	tar_options="--create --gzip --file"

	if [ -f "${DIR}/deploy/${KERNEL_UTS}${deployfile}" ] ; then
		rm -rf "${DIR}/deploy/${KERNEL_UTS}${deployfile}" || true
	fi

	if [ -d "${DIR}/deploy/tmp" ] ; then
		rm -rf "${DIR}/deploy/tmp" || true
	fi
	mkdir -p "${DIR}/deploy/tmp"

	echo "-----------------------------"
	echo "Building ${pkg} archive..."

	case "${pkg}" in
	modules)
    	echo "make -s ARCH=${KERNEL_ARCH} CROSS_COMPILE=\"${CC}\" modules_install INSTALL_MOD_PATH=\"${DIR}/deploy/tmp\""
	    echo "-----------------------------"
		make -s ARCH=${KERNEL_ARCH} CROSS_COMPILE="${CC}" modules_install INSTALL_MOD_PATH="${DIR}/deploy/tmp"
		;;
	dtbs)
		make -s ARCH=${KERNEL_ARCH} CROSS_COMPILE="${CC}" dtbs_install INSTALL_DTBS_PATH="${DIR}/deploy/tmp"
		;;
	esac

	echo "Compressing ${KERNEL_UTS}${deployfile}..."
	cd "${DIR}/deploy/tmp" || true
	tar ${tar_options} "../${KERNEL_UTS}${deployfile}" ./*

	cd "${DIR}/" || exit
	rm -rf "${DIR}/deploy/tmp" || true

	if [ ! -f "${DIR}/deploy/${KERNEL_UTS}${deployfile}" ] ; then
		export ERROR_MSG="File Generation Failure: [${KERNEL_UTS}${deployfile}]"
		/bin/sh -e "${DIR}/scripts/error.sh" && { exit 1 ; }
	else
		ls -lh "${DIR}/deploy/${KERNEL_UTS}${deployfile}"
	fi
}

make_modules_pkg () {
	pkg="modules"
	make_pkg
}

make_dtbs_pkg () {
	pkg="dtbs"
	make_pkg
}

make_gpu_driver() {
    
    cd ${DIR}/gcnano-driver-6.4.3

    make KERNEL_DIR=${DIR}/linux CROSS_COMPILE="${CC}" clean
    make KERNEL_DIR=${DIR}/linux CROSS_COMPILE="${CC}" all

    cd "${DIR}/"

}

copy_defconfig

make_menuconfig

make_kernel

make_modules_pkg

make_dtbs_pkg

make_gpu_driver

echo "-----------------------------"
echo "Script Complete"
echo "${KERNEL_UTS}" > kernel_version
echo "eewiki.net: [user@localhost:~$ export kernel_version=${KERNEL_UTS}]"
echo "-----------------------------"

/bin/sh -e "${DIR}/create-rootfs.sh" || { exit 1 ; }