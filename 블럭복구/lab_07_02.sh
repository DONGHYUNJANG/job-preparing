#!/bin/bash
# Oracle Database 10g: Administration Workshop II
# Oracle Server Technologies - Curriculum Development
#
# ***Training purposes only***
# ***Not appropriate for production use***
#

FILE=${1:?'Parameter 1 should be set to file name'}
BLOCK=${2:?'Parameter 2 should be set to the block to be corrupted'}
BLOCKSIZE=${3:?'Parameter 3 should be set to the database block size'}

dd of=$FILE bs=$BLOCKSIZE conv=notrunc seek=$BLOCK <<EOF
CORRUPT
EOF
dd of=$FILE bs=$BLOCKSIZE conv=notrunc seek=`expr 1 + $BLOCK` <<EOF
CORRUPT
EOF
dd of=$FILE bs=$BLOCKSIZE conv=notrunc seek=`expr 2 + $BLOCK` <<EOF
CORRUPT
EOF
dd of=$FILE bs=$BLOCKSIZE conv=notrunc seek=`expr 3 + $BLOCK` <<EOF
CORRUPT
EOF
