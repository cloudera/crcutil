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

echo "Generating preliminary configure.ac"
autoscan

sed 's/^AC_INIT(.*$/AC_INIT(crcutil, 1.0, crcutil@googlegroups.com)\
AM_INIT_AUTOMAKE([foreign -Wall -Werror])\
AC_PROG_RANLIB() \
AC_CONFIG_FILES([Makefile]) \
AC_OUTPUT()/' configure.scan >configure.ac

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

# --pedantic -std=c99?
crcutil_flags="-DCRCUTIL_USE_MM_CRC32=1 -Wall -msse2 -Icode -Iexamples -Itests -fPIC"
crcutil_flags="${crcutil_flags} -O3"
if [[ "$(c++ -dumpversion)" > "4.4.9" ]]; then
  crcutil_flags="${crcutil_flags} -mcrc32"
fi

echo>>${target} "AM_CXXFLAGS=${crcutil_flags}"
if [ "$(uname -a | grep ^Darwin)" == "" ] && [[ "$(c++ -dumpversion)" > "4.4.9" ]]; then
  # Static linking is not supported on Mac OS X.
  # Use static linking on Linux, otherwise GCC 4.5.0 linker produces
  # obscure warning (well, the code works but nevertheless).
  echo>>${target} "AM_LDFLAGS=-static"
fi
echo>>${target} 'AM_CFLAGS=$(AM_CXXFLAGS)'
echo>>${target} "check_PROGRAMS=crcutil_ut"
echo>>${target} "TESTS=crcutil_ut"
sources=$(ls tests/*.cc tests/*.c tests/*.h code/*.cc code/*.h | grep -v intrinsic | tr "\n" " ")
echo>>${target} "crcutil_ut_SOURCES=${sources}"

# Don't install the crcutil "usage" example program.
echo>>${target} "noinst_PROGRAMS=usage"
echo>>${target} 'usage_CXXFLAGS=$(AM_CXXFLAGS) -Itests'
sources=$(ls examples/*.cc examples/*.h code/*.cc code/*.h tests/aligned_alloc.h | grep -v intrinsic | tr "\n" " ")
echo>>${target} "usage_SOURCES=${sources}"

# Build a static library.
echo>>${target} "lib_LIBRARIES=libcrcutil.a"
libsources=$(ls examples/interface.cc examples/interface.h code/*.cc code/*.h tests/aligned_alloc.h | grep -v intrinsic | tr "\n" " ")
echo>>${target} "libcrcutil_a_SOURCES=${libsources}"
echo>>${target} "crcutilhdrsdir=\$(includedir)/crcutil"
echo>>${target} "crcutilhdrs_HEADERS=examples/interface.h"

echo "Creating Makefile.in"
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
