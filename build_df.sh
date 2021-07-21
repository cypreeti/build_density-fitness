#!/bin/bash
#This script is to generate the density-fitness executable.
#It requires CCP4 root directory and thread (used for make )as input.
#   Usage:build_df.sh options -c CCP4_ROOT_DIR, -n THREADS -h for help
#   this first install gcc 9.3 and boost 1.75.0, after which all the dependencies of density-fitness are installed, followed by compling density-fitness executable 
# creates my_tools and my_libs folders in current directory and uses for downloading and installing various libraries respectively.


my_use="Usage: `basename $0` options -c CCP4_ROOT_DIR, -n THREADS -h for help"

if ( ! getopts ":c:n:h:" opt); then
	echo $my_use;
	exit $E_OPTERROR;
fi

while getopts ":c:n:h:" opt; do
  case $opt in
    c) CCP4_ROOT="$OPTARG"
    ;;
   \?)
      echo "Invalid option: -$OPTARG" >&2
      echo $my_use;
      exit 1
      ;;
    n) NPROC="$OPTARG"
    ;;
   \?)
      echo "Invalid option: -$OPTARG" >&2
      echo $my_use;
      exit 1
      ;;
    h) help="$OPTARG"
    ;;
   \?)
      echo $my_use;
      exit 1
      ;;
  esac
done

if (($# != 4)); then
  echo "Argument missing"
  echo $my_use;
  exit $E_OPTERROR;
fi


SOURCE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR=SOURCE_DIR
WORKDIR=${BASE_DIR}"/my_tools/"
#if you change INSTALL_LIB_DIR, please change it in newuoa.pc aswell.
INSTALL_LIB_DIR=${BASE_DIR}"/my_libs/"



mkdir -p $WORKDIR
mkdir -p $INSTALL_LIB_DIR


# Build a gcc with version GCC_VERSION = 9.3
# We only need the C++ compiler
cd $WORKDIR 
GCC_VERSION=9.3.0 
wget https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.gz 
tar xzvf gcc-${GCC_VERSION}.tar.gz 
mkdir obj.gcc-${GCC_VERSION} 
cd gcc-${GCC_VERSION} 
./contrib/download_prerequisites 
cd ../obj.gcc-${GCC_VERSION} 
../gcc-${GCC_VERSION}/configure --disable-multilib --enable-languages=c,c++ --program-suffix=-9 --prefix=$INSTALL_LIB_DIR
make -j $(NPROC) 
make install

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$INSTALL_LIB_DIR/lib/../lib64
export PATH=$PATH:$INSTALL_LIB_DIR/bin/

# Install Boost 1_75_0
cd $WORKDIR
wget https://boostorg.jfrog.io/artifactory/main/release/1.75.0/source/boost_1_75_0.tar.gz
tar xvf boost_1_75_0.tar.gz
# Use our own user-config.jam file to make sure the new compiler is used
cp $SOURCE_DIR/user-config.jam $WORKDIR/boost_1_75_0/
cd $WORKDIR/boost_1_75_0/ 
./bootstrap.sh --prefix=$INSTALL_LIB_DIR/boost_1_75_0/
./b2 link=static --toolset=gcc-9 install --without-python --prefix=$INSTALL_LIB_DIR/boost_1_75_0/


#Install mrc
#This requires ccp4 
export LDFLAGS=-static-libstdc++ CXX=g++-9 CCP4=$CCP4_ROOT  CLIBD=$CCP4_ROOT/lib/data
cd $WORKDIR 
git clone https://github.com/mhekkel/mrc.git
cd mrc
./configure --prefix=$INSTALL_LIB_DIR/mrc/ --with-boost=$INSTALL_LIB_DIR/boost_1_75_0
make 
make install 

#Install libcifpp 
cd $WORKDIR 
git clone https://github.com/PDB-REDO/libcifpp.git 
cd libcifpp
export DATA_CACHE_DIR=$INSTALL_LIB_DIR/libcifpp_cache
export DATA_LIB_DIR=$INSTALL_LIB_DIR/libcifpp_lib
export MRC=$INSTALL_LIB_DIR/mrc/bin/mrc
./configure --enable-resources --prefix=$INSTALL_LIB_DIR/libcifpp --exec-prefix=$INSTALL_LIB_DIR/libcifpp_exe --with-boost=$INSTALL_LIB_DIR/boost_1_75_0 
make -j $(NPROC) 
make install


# Install libzeep
git clone https://github.com/mhekkel/libzeep.git 
cd libzeep 
./configure --prefix=$INSTALL_LIB_DIR/libzeep/ --with-boost=$INSTALL_LIB_DIR/boost_1_75_0
make -j $(NPROC)
make install


## Install libnewuoa
cd $WORKDIR
git clone https://github.com/elsid/newuoa-cpp.git
cd newuoa-cpp/
g++-9 -o libnewuoa.a -r -fpic -I include src/newuoa.cpp
mkdir -p $INSTALL_LIB_DIR/local/lib/
install libnewuoa.a $INSTALL_LIB_DIR/local/lib/libnewuoa.a
mkdir -p $INSTALL_LIB_DIR/local/include/
install include/newuoa.h $INSTALL_LIB_DIR/local/include/newuoa.h


# Install libpdb-redo
cd $WORKDIR
git clone https://github.com/PDB-REDO/libpdb-redo.git
cd libpdb-redp 
wget https://ftp.ebi.ac.uk/pub/databases/pdb/data/monomers/components.cif.gz  --no-check-certificate
mkdir data 
mv components.cif.gz data/
export GSL_LIBS=$CCP4_ROOT/lib/
export NEWUOA_LDFLAGS=-L/$INSTALL_LIB_DIR/local/lib
export NEWUOA_CPPFLAGS=-I/$INSTALL_LIB_DIR/local/include
##for it to find newuoa.pc
export PKG_CONFIG_PATH=PKG_CONFIG_PATH:$SOURCE_DIR
./configure --enable-resources --prefix=$INSTALL_LIB_DIR/libpdb-redo --exec-prefix=$INSTALL_LIB_DIR/libpdb-redo_exe --with-boost=$INSTALL_LIB_DIR/boost_1_75_0  --with-zeep=$INSTALL_LIB_DIR/libzeep/ --with-cif++=$INSTALL_LIB_DIR/libcifpp/ CFLAGS=-I/$INSTALL_LIB_DIR/local/include LDFLAGS=-L/$INSTALL_LIB_DIR/local/lib 
make -j $(NPROC) 
make install



##install density-fitness
cd $WORKDIR
wget https://mmcif.wwpdb.org/dictionaries/ascii/mmcif_pdbx_v50.dic.gz
gunzip mmcif_pdbx_v50.dic.gz
git clone https://github.com/PDB-REDO/density-fitness.git
cd density-fitness
export LIBCIFPP_DATA_DIR=$WORKDIR
export ZEEP_CPPFLAGS=$INSTALL_LIB_DIR/libzeep/include 
export ZEEP_LDFLAGS=$INSTALL_LIB_DIR/libzeep/lib
export NEWUOA_LDFLAGS=$INSTALL_LIB_DIR/local/lib
export NEWUOA_CPPFLAGS=$INSTALL_LIB_DIR/local/include
export PDB_REDO_LDFLAGS=$INSTALL_LIB_DIR/libpdb-redo/lib
export PDB_REDO_CPPFLAGS=$INSTALL_LIB_DIR/libpdb-redo/include
export CIFPP_LDFLAGS=$INSTALL_LIB_DIR/libcifpp/lib
export CIFPP_CPPFLAGS=$INSTALL_LIB_DIR/libcifpp/include
./configure --enable-resources --prefix=$INSTALL_LIB_DIR/density-fitness --exec-prefix=$INSTALL_LIB_DIR/density-fitness_exe --with-boost=$INSTALL_LIB_DIR/boost_1_75_0  --with-zeep=$INSTALL_LIB_DIR/libzeep/ --with-cif++=$INSTALL_LIB_DIR/libcifpp/ --with-pdb-redo=$INSTALL_LIB_DIR/libpdb-redo
make 
make install 
##density-fitness executeable should be generated in same dir (this can then be copied to tools-dir for further use)

echo "Installation complete!"




