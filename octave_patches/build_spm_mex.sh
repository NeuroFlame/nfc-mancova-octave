#!/bin/bash
# Builds the 3 SPM8 MEX functions GIFT's .m stubs require and that MATLAB
# ships pre-compiled but Octave does not (spm_slice_vol, spm_sample_vol,
# spm_bwlabel -- the one other stub, spm_existfile, already has a working
# non-compiled fallback elsewhere in GIFT, so it's skipped here).
#
# SPM8's own C source has a handful of 32-bit-vs-64-bit MEX API mismatches
# (declaring `const int *` for values mxGetDimensions() returns as
# `const mwSize *`, i.e. 4-byte vs 8-byte elements) that real MATLAB's mex
# compiler tolerates but Octave's mkoctfile does not -- confirmed the hard
# way: an uncorrected build ran, but spm_bwlabel crashed with "failed to
# allocate -6601171057795000320 bytes of memory" because mxCreateNumericArray
# read the output dimensions at the wrong stride. Patched below before
# compiling.
set -euo pipefail

SRC_DIR="${1:?usage: build_spm_mex.sh <spm8-src-dir> <output-dir> <private-output-dir>}"
OUT_DIR="${2:?usage: build_spm_mex.sh <spm8-src-dir> <output-dir> <private-output-dir>}"
PRIVATE_OUT_DIR="${3:?usage: build_spm_mex.sh <spm8-src-dir> <output-dir> <private-output-dir>}"

BUILD_DIR="$(mktemp -d)"
cp "$SRC_DIR"/*.c "$SRC_DIR"/*.h "$BUILD_DIR"/
cd "$BUILD_DIR"

# --- 64-bit MEX API fixes (see header comment) ---
sed -i '292s/const int      \*cdim/const mwSize   *cdim/' spm_bwlabel.c
# Content-based (not line-number-based) so it's unaffected by the insertion below shifting line numbers.
sed -i 's/mxCreateNumericArray(ndim,dim,mxDOUBLE_CLASS,mxREAL);/mxCreateNumericArray(ndim,mw_dim,mxDOUBLE_CLASS,mxREAL);/' spm_bwlabel.c
sed -i '343a\   mwSize mw_dim[3]; mw_dim[0]=(mwSize)dim[0]; mw_dim[1]=(mwSize)dim[1]; mw_dim[2]=(mwSize)dim[2];' spm_bwlabel.c
sed -i '66s/const int \*dims;/const mwSize *dims;/' spm_mapping.c
sed -i '432s/const int \*dims;/const mwSize *dims;/' spm_mapping.c
sed -i '464s/const int \*dims;/const mwSize *dims;/' spm_mapping.c

# --- spm_vol_utils.a: spm_vol_utils.c compiled once per supported NIfTI/
# ANALYZE datatype (plus byte-swapped variants), archived with the shared
# mapping/access helpers. Mirrors src/Makefile's OBS + archive rule exactly.
for pair in SPM_UNSIGNED_CHAR:uchar SPM_SIGNED_SHORT:short SPM_SIGNED_INT:int \
            SPM_SIGNED_CHAR:schar SPM_UNSIGNED_SHORT:ushort SPM_UNSIGNED_INT:uint \
            SPM_FLOAT:float SPM_DOUBLE:double; do
  def="${pair%%:*}"; name="${pair##*:}"
  mkoctfile --mex -c spm_vol_utils.c -D"$def" -o "utils_${name}.o"
done
for pair in SPM_SIGNED_SHORT:short_s SPM_SIGNED_INT:int_s \
            SPM_UNSIGNED_SHORT:ushort_s SPM_UNSIGNED_INT:uint_s \
            SPM_FLOAT:float_s SPM_DOUBLE:double_s; do
  def="${pair%%:*}"; name="${pair##*:}"
  mkoctfile --mex -c spm_vol_utils.c -D"$def" -DSPM_BYTESWAP -o "utils_${name}.o"
done
mkoctfile --mex -c spm_make_lookup.c -o spm_make_lookup.o
mkoctfile --mex -c spm_getdata.c -o spm_getdata.o
mkoctfile --mex -c spm_vol_access.c -o spm_vol_access.o
mkoctfile --mex -c spm_mapping.c -o spm_mapping.o

ar rcs spm_vol_utils.a utils_*.o spm_make_lookup.o spm_getdata.o spm_vol_access.o spm_mapping.o

# GIFT calls these through its own icatb_spm_*.m wrapper names, not SPM8's
# original spm_*.m names. Those wrappers are plain error() stubs meant to be
# shadowed by a compiled binary of the SAME name (MEX dispatch is purely by
# filename -- the mexFunction C entry point has no name of its own) -- so
# the compiled output must be named icatb_spm_*, not spm_*, or Octave keeps
# loading the always-throws .m stub instead.
mkoctfile --mex spm_sample_vol.c spm_vol_utils.a -o icatb_spm_sample_vol.mex
mkoctfile --mex spm_slice_vol.c spm_vol_utils.a -o icatb_spm_slice_vol.mex
mkoctfile --mex spm_bwlabel.c -o icatb_spm_bwlabel.mex

mkdir -p "$OUT_DIR"
cp icatb_spm_sample_vol.mex icatb_spm_slice_vol.mex icatb_spm_bwlabel.mex "$OUT_DIR"/

# mat2file/file2mat back the @icatb_file_array class's memory-mapped file
# I/O (used by its subsasgn/subsref). GIFT's vendored copy already ships
# prebuilt binaries for several platforms (icatb_mat2file.mexa64/.mexmaci64/
# etc, right beside the .m stub, in @icatb_file_array/private/) -- just none
# for Octave, and none for arm64 either way. These are MATLAB "private"
# class functions, resolved from their class folder's private/ directory
# rather than the general path, so the compiled output has to land in that
# exact directory (passed in as $PRIVATE_OUT_DIR), not the general compat
# directory the other 3 functions above use.
mkoctfile --mex mat2file.c -o icatb_mat2file.mex
mkoctfile --mex file2mat.c -o icatb_file2mat.mex
mkdir -p "$PRIVATE_OUT_DIR"
cp icatb_mat2file.mex icatb_file2mat.mex "$PRIVATE_OUT_DIR"/
cd /
rm -rf "$BUILD_DIR"
