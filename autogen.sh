#!/bin/bash -e

# See http://mij.oltrelinux.com/devel/autoconf-automake/

if [ -f "Makefile" ] && [ -f "Makefile.am" ] && [ -f "Makefile.in" ] && [ -d ".deps" ] ; then
  make clean
fi

echo "Removing old garbage"
if [ "${1}" != "clean" ] || [ "${2}" == "clean" ]; then
# "./mk.sh clean" leave all the files needed for "./configure && make".
# "./mk.sh clean clean" deletes them as well.
# Full clean build starts from removing all generated files.
  rm -f Makefile
  rm -f Makefile.am
  rm -f Makefile.in
  rm -f aclocal.m4
  rm -f config.h.in
  rm -f configure
  rm -f configure.ac
  rm -f depcomp
  rm -f install-sh
  rm -f missing
fi

rm -f autoscan.log
rm -f config.h
rm -f config.log
rm -f config.status
rm -f stamp-h1
if [ -d "autom4te.cache" ]; then
  rm -r autom4te.cache
fi
if [ -d ".deps" ]; then
  rm -r .deps
fi

if [ "${1}" == "clean" ]; then
  exit
fi

CXX="${CXX:-g++}"
CXX=$(which "$CXX")
if [ ! -x "$CXX" ]; then
  echo "Error: cannot find C++: $CXX"
  exit 1
fi

CXX_VERSION=$($CXX --version | head -1)
IS_CLANG=0
echo $CXX_VERSION | grep -q "clang" && IS_CLANG=1
KERNEL_NAME=$(uname -s)
PROCESSOR=$(uname -p)

if [ ! -d m4 ]; then
  echo "Creating m4 directory"
  mkdir m4
fi

echo "Generating preliminary configure.ac"
autoscan

sed -e 's/^AC_INIT(.*$/AC_INIT(crcutil, 1.0, crcutil@googlegroups.com)\
AM_INIT_AUTOMAKE([foreign subdir-objects])\
LT_INIT() \
AC_CONFIG_FILES([Makefile]) \
AC_CONFIG_MACRO_DIR([m4]) \
AC_OUTPUT()/' \
-e 's/AC_PROG_RANLIB//' configure.scan >configure.ac


# AC_OUTPUT(Makefile)/' configure.scan >configure.ac
rm -f configure.scan

echo "Generating final configure.ac"
aclocal
autoconf

echo "Generating config.h.in"
autoheader

target=./Makefile.am
echo "Generating ${target}"
echo>${target} "AUTOMAKE_OPTIONS=foreign"
echo>${target} "ACLOCAL_AMFLAGS=-I m4"

# --pedantic -std=c99?
crcutil_flags="-DCRCUTIL_USE_MM_CRC32=1 -Wall -Icode -Iexamples -Itests"
crcutil_flags="${crcutil_flags} -O3"
if [[ "$PROCESSOR" == "ppc64le" ]]; then
  crcutil_flags="${crcutil_flags}"
elif [[ "$PROCESSOR" == "aarch64" ]]; then
  crcutil_flags="${crcutil_flags} -march=armv8-a"
elif [[ "$IS_CLANG" = "0" ]]; then
  # Newer GCC versions output just the major version with -dumpversion flag,
  # but older GCC versions don't even recognize the -dumpfullversion flag which
  # should be used in newer versions to output major, minor, and patch versions.
  # But those "newer versions" are newer than GCC 5, so in the context
  # of comparision with GCC 4.4.9 -dumpversion suffices.
  version="$(${CXX} -dumpversion)"
  ver_major=$(echo $version | cut -d . -f 1)
  if [ -z "$ver_major" ]; then
    echo "could not determine GCC major version"
    exit 1
  fi
  ver_minor=$(echo $version | cut -d . -f 2 -s)
  ver_minor=${ver_minor:-0}
  ver_patch=$(echo $version | cut -d . -f 3 -s)
  ver_patch=${ver_patch:-0}
  # For simplicity, compare the versions using the lexicographical ordering.
  ver_str=$(printf %03d.%03d.%03d $ver_major $ver_minor $ver_patch)
  if [[ "$ver_str" > "004.004.009" ]]; then
    crcutil_flags="${crcutil_flags} -msse2 -mcrc32"
  fi
elif [[ "$IS_CLANG" = "1" ]]; then
  crcutil_flags="${crcutil_flags} -msse2 -msse4.2"
fi

echo>>${target} "AM_CXXFLAGS=${crcutil_flags}"
echo>>${target} 'AM_CFLAGS=$(AM_CXXFLAGS)'

# Build tests.
echo>>${target} "check_PROGRAMS=crcutil_ut"
echo>>${target} "TESTS=crcutil_ut"
sources=$(ls tests/*.cc tests/*.c tests/*.h code/*.cc code/*.h | grep -v intrinsic | tr "\n" " ")
echo>>${target} "crcutil_ut_CXXFLAGS = \$(AM_CXXFLAGS)" # get our own build work dir
echo>>${target} "crcutil_ut_SOURCES=${sources}"

# Build, but don't install the crcutil "usage" example program.
echo>>${target} "noinst_PROGRAMS=usage"
echo>>${target} 'usage_CXXFLAGS=$(AM_CXXFLAGS) -Itests'
sources=$(ls examples/*.cc examples/*.h code/*.cc code/*.h tests/aligned_alloc.h | grep -v intrinsic | tr "\n" " ")
echo>>${target} "usage_SOURCES=${sources}"

# Build both a static and a dynamic library.
libsources=$(ls examples/interface.cc examples/interface.h code/*.cc code/*.h tests/aligned_alloc.h | grep -v intrinsic | tr "\n" " ")
echo>>${target} "lib_LTLIBRARIES = libcrcutil.la"
echo>>${target} "libcrcutil_la_CXXFLAGS = \$(AM_CXXFLAGS) -fPIC"
echo>>${target} "libcrcutil_la_SOURCES = ${libsources}"
echo>>${target} "libcrcutil_la_LDFLAGS = -version-info 0:0:0"
echo>>${target} "crcutilhdrsdir=\$(includedir)/crcutil"
echo>>${target} "crcutilhdrs_HEADERS=examples/interface.h"

echo "Creating Makefile.in"
case "$KERNEL_NAME" in
  Darwin*) glibtoolize ;;
  *) libtoolize ;;
esac

aclocal
automake --add-missing
autoconf

echo ""
echo "Configured the library."
echo "Library configuration flags:"
echo "  ${crcutil_flags}"
echo "You may now run ./configure && make && make install"
echo ""

exit 0

#./configure CXXFLAGS="${cflags}" CFLAGS="${cflags}"
#make $1
