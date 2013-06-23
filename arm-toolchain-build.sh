#!/bin/bash
#
# Written by Uwe Hermann <uwe@hermann-uwe.de>, released as public domain.
# Modified by Piotr Esden-Tempski <piotr@esden.net>, released as public domain.
# Modified by Christophe Duparquet <e39@free.fr>, released as public domain.
# Modified by Matthias Blaicher <matthias@blaicher.com>, released as public domain

# This script will build a GNU ARM toolchain in the directory arm-toolchain.
# Process can be suspended and restarted at will.
# Packages are downloaded to arm-toolchain/archives/.
# Packages are extracted to arm-toolchain/sources/.
# Packages are built in arm-toolchain/build/.
# arm-toolchain/install contains the result of make install for each tool.
# arm-toolchain/status contains the status of each part of the process (logs, errors...)

# PACKAGE_DESCRIPTION = BASE_URL ARCHIVE_BASENAME PACKAGE_VERSION ARCHIVE_TYPE URL_OPTIONS
#
BINUTILS="http://ftp.gnu.org/gnu/binutils binutils 2.23.1 tar.bz2"
GCC="ftp://ftp.lip6.fr/pub/gcc/releases/gcc-4.8.1 gcc 4.8.1 tar.bz2"
GDB="http://ftp.gnu.org/gnu/gdb gdb 7.6 tar.bz2"
NEWLIB="ftp://sources.redhat.com/pub/newlib newlib 1.20.0 tar.gz"

TARGET=arm-none-eabi			# Or: TARGET=arm-elf

BASEDIR=$(pwd)/arm-toolchain		# Base directory
ARCHIVES=${BASEDIR}/archives		# Where to store downloaded packages
SOURCES=${BASEDIR}/sources		# Where to extract packages
BUILD=${BASEDIR}/build			# Where to build packages
STATUS=${BASEDIR}/status		# Where to store building process status
PREFIX=${BASEDIR}/install		# Install location of your final toolchain

PARALLEL=-j$(getconf _NPROCESSORS_ONLN)

MULTILIB_LIST="--with-multilib-list=armv6-m,armv7-m,armv7e-m,armv7-r"

# Find python2 command. If python2 is not known, assume that python refers 
# to it.
if which python2 &> /dev/null; then
  PYTHON_PATH=$(which python2)
else
  PYTHON_PATH=$(which python)
fi

export PATH="${PREFIX}/bin:${PATH}"
mkdir -p ${ARCHIVES} ${SOURCES} ${BUILD} ${STATUS}


die() {
    echo -e "\n\n**FAIL**"
    tail ${CMD}
    # echo -e "\nIn ${ERR} :"
    tail ${ERR}
    echo
    exit
}


context() {
    URL=$1
    ANAME=$2
    AVERSION=$3
    ATYPE=$4
    URL_OPTIONS=$5

    SOURCE=$ANAME-$AVERSION
    ARCHIVE=$SOURCE.$ATYPE
}


fetch() {
    CMD=${STATUS}/${SOURCE}.fetch.cmd
    LOG=${STATUS}/${SOURCE}.fetch.log
    ERR=${STATUS}/${SOURCE}.fetch.errors
    DONE=${STATUS}/${SOURCE}.fetch.done

    if [ -e ${DONE} ]; then
     	echo "${SOURCE} already fetched"
     	return
    fi

    case ${URL} in
        http://*)
            COMMAND=wget
            ;;
        ftp://*)
            COMMAND=wget
            ;;
        git://*)
            COMMAND=git
            ;;
        *)
            echo "${URL}: unknown protocol." >${ERR}
            die
    esac

    case $COMMAND in
        wget)
            cd "$ARCHIVES"
            echo -n "Downloading $ARCHIVE ... "
            echo wget -c $URL_OPTIONS "$URL/$ARCHIVE" >${CMD}
            wget -c $URL_OPTIONS "$URL/$ARCHIVE" >${LOG} 2>${ERR} || die
            ;;
        git)
            cd "$SOURCES"
            rm -rf "$ANAME-git"
            echo -n "Downloading $SOURCE ... "
            echo git clone "$URL/$ANAME.git" >${CMD}
            ((git clone "$URL/$ANAME.git" || git clone "$URL/$ANAME") \
                && mv ${ANAME} ${ANAME}-git) >${LOG} 2>${ERR} || die
            ;;
    esac
    echo "OK."
    touch ${DONE}
}


extract() {
    CMD=${STATUS}/${SOURCE}.extract.cmd
    LOG=${STATUS}/${SOURCE}.extract.log
    ERR=${STATUS}/${SOURCE}.extract.errors
    DONE=${STATUS}/${SOURCE}.extract.done

    cd ${BASEDIR}
    if [ -e ${DONE} ] ; then
	echo "${SOURCE} already extracted"
    else
	echo -n "Extracting ${SOURCE} ... "
	cd ${SOURCES}
	case ${ATYPE} in
	    tar.gz)
		COMMAND=xvzf
		;;
	    tar.bz2)
		COMMAND=xvjf
		;;
	    dir)
		COMMAND=""
		cp -a "$SOURCES/$SOURCE" "$BUILD/$SOURCE"
		;;
	    *)
		if [ -d ${ARCHIVES}/${ARCHIVE} ] ; then
		    ln -s ${ARCHIVES}/${ARCHIVE} .
		    ln -s ${ARCHIVES}/${ARCHIVE} ${BUILD}
		    touch ${DONE}
		    return
		else
		    echo "${ARCHIVE}: unknown archive format." >${ERR}
		    die
		fi
	esac
	if [ -n "$COMMAND" ] ; then
	    echo "tar $COMMAND ${ARCHIVES}/${ARCHIVE}" >${CMD}
	    tar $COMMAND ${ARCHIVES}/${ARCHIVE} >${LOG} 2>${ERR} || die
	fi
	echo "OK."
	touch ${DONE}
    fi
}


configure() {
    OPTIONS=$*

    unset ZPASS
    [ -z "$PASS" ] || ZPASS=".$PASS"
    CMD=${STATUS}/${SOURCE}.configure${ZPASS}.cmd
    LOG=${STATUS}/${SOURCE}.configure${ZPASS}.log
    ERR=${STATUS}/${SOURCE}.configure${ZPASS}.errors
    DONE=${STATUS}/${SOURCE}.configure${ZPASS}.done

    cd ${BASEDIR}
    if [ -e ${DONE} ]; then
	echo "${SOURCE} already configured"
    else
	echo -n "Configuring ${SOURCE} ... "
	mkdir -p ${BUILD}/${SOURCE}
	cd ${BUILD}/${SOURCE}
	echo "${SOURCES}/${SOURCE}/configure $OPTIONS" >${CMD}
	${SOURCES}/${SOURCE}/configure $OPTIONS >${LOG} 2>${ERR} || die
	echo "OK."
	touch ${DONE}
    fi
    unset PASS ZPASS
}


domake() {
    WHAT=$1 ; shift
    OPTIONS=$*
    
    [ -z "$WHAT" ] || ZWHAT=".$WHAT"
    [ -z "$PASS" ] || ZPASS=".$PASS"
    CMD=${STATUS}/${SOURCE}.make${ZWHAT}${ZPASS}.cmd
    LOG=${STATUS}/${SOURCE}.make${ZWHAT}${ZPASS}.log
    ERR=${STATUS}/${SOURCE}.make${ZWHAT}${ZPASS}.errors
    DONE=${STATUS}/${SOURCE}.make${ZWHAT}${ZPASS}.done

    cd ${BASEDIR}
    if [ -e ${DONE} ]; then
	echo "Make ${SOURCE} \"${WHAT}\" already done"
    else
	echo -n "Make ${SOURCE} \"${WHAT}\" ... "
	cd ${BUILD}/${SOURCE}
	echo "make ${WHAT} $OPTIONS" >${CMD}
	if [ -z "$VAR" ]; then
	  make ${PARALLEL} ${WHAT}  >${LOG} 2>${ERR} || die
	else
	  make ${PARALLEL} ${WHAT} "$OPTIONS" >${LOG} 2>${ERR} || die
	fi
	echo "OK."
	touch ${DONE}
    fi
    unset PASS ZPASS ZWHAT
}


# Binutils
#
context $BINUTILS
fetch
extract
configure \
    --target=${TARGET} \
    --prefix=${PREFIX} \
    --disable-nls \
    --enable-plugins \
    --disable-werror
domake
domake install


# GCC pass 1
#
context $GCC
fetch
extract
PASS=1 configure \
    --target=${TARGET} \
    --prefix=${PREFIX} \
    --enable-languages=c \
    --disable-decimal-float \
    --disable-libffi \
    --disable-libgomp \
    --disable-libmudflap \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libstdcxx-pch \
    --disable-nls \
    --disable-shared \
    --disable-threads \
    --disable-tls \
    --with-newlib \
    --without-headers \
    --with-gnu-as \
    --with-gnu-ld \
    --disable-werror\
    --with-cloog\
      ${MULTILIB_LIST}
    
PASS=1 domake all-gcc
PASS=1 domake install-gcc

# Newlib
#
context $NEWLIB
fetch
extract
configure \
    --target=${TARGET} \
    --prefix=${PREFIX} \
    --enable-interwork \
    --enable-multilib \
    --with-gnu-as \
    --with-gnu-ld \
    --disable-nls \
    --disable-werror \
    --disable-newlib-supplied-syscalls \
    --enable-newlib-io-long-long \
    --enable-newlib-reent-small \
    --enable-newlib-register-fini \
    --enable-target-optspace
    #--enable-newlib-hw-fp
domake
domake install


# GCC pass 2
#
context $GCC
PASS=2 configure \
    --target=${TARGET} \
    --prefix=${PREFIX} \
    --enable-languages=c,c++ \
    --disable-decimal-float \
    --disable-libffi \
    --disable-libgomp \
    --disable-libmudflap \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libstdcxx-pch \
    --disable-nls \
    --disable-shared \
    --disable-threads \
    --disable-tls \
    --with-newlib \
    --without-headers \
    --with-gnu-as \
    --with-gnu-ld \
    --disable-werror\
    --with-cloog\
      ${MULTILIB_LIST} \
    --enable-cxx-flags="-fno-exceptions"
    
PASS=2 domake all "CXXFLAGS_FOR_TARGET='-g -Os -ffunction-sections -fdata-sections -fno-exceptions'"
PASS=2 domake install

# GDB
#
context $GDB
fetch
extract
configure \
    --target=${TARGET} \
    --prefix=${PREFIX} \
    --enable-interwork \
    --enable-multilib \
    --disable-werror \
    --with-python=${PYTHON_PATH} \
    --with-system-readline
domake
domake install