#!/bin/bash -eu

# Copyright 2016 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# It's not a good idea to link an MSYS dynamic library into a native Windows
# JVM, so we need to build it with Visual Studio. However, Bazel doesn't
# support multiple compilers in the same build yet, so we need to hack around
# this limitation using a genrule.

DLL="$1"
shift 1

function fail() {
  echo >&2 "ERROR: $@"
  exit 1
}

# Ensure the PATH is set up correctly.
if ! which which >&/dev/null ; then
  PATH="/bin:/usr/bin:$PATH"
  which which >&/dev/null \
      || fail "System PATH is not set up correctly, cannot run GNU bintools"
fi

# Create a temp directory. It will used for the batch file we generate soon and
# as the temp directory for CL.EXE .
VSTEMP=$(mktemp -d)
trap "rm -fr \"$VSTEMP\"" EXIT

# Find Visual Studio. We don't have any regular environment variables available
# so this is the best we can do.
if [ -z "${BAZEL_VS+set}" ]; then
  VSVERSION="$(ls "C:/Program Files (x86)" \
      | grep -E "Microsoft Visual Studio [0-9]+" \
      | sort --version-sort \
      | tail -n 1)"
  [[ -n "$VSVERSION" ]] || fail "Visual Studio not found"
  BAZEL_VS="C:/Program Files (x86)/$VSVERSION"
fi
VSVARS="${BAZEL_VS}/VC/VCVARSALL.BAT"

# Find Java. $(JAVA) in the BUILD file points to external/local_jdk/..., which
# is not very useful for anything not MSYS-based.
JAVA=$(ls "C:/Program Files/java" | grep -E "^jdk" | sort | tail -n 1)
[[ -n "$JAVA" ]] || fail "JDK not found"
JAVAINCLUDES="C:/Program Files/java/$JAVA/include"

# Convert all compilation units to Windows paths.
WINDOWS_SOURCES=()
for i in $*; do
  if [[ "$i" =~ ^.*\.cc$ ]]; then
    WINDOWS_SOURCES+=("$(cygpath -a -w $i)")
  fi
done

# CL.EXE needs a bunch of environment variables whose official location is a
# batch file. We can't make that have an effect on a bash instance, so
# generate a batch file that invokes it.
cat > "${VSTEMP}/windows_jni.bat" <<EOF
@echo OFF
@call "${VSVARS}" amd64
@set TMP=$(cygpath -a -w "${VSTEMP}")
@CL /O2 /EHsc /LD /Fe:"$(cygpath -a -w ${DLL})" /I "${JAVAINCLUDES}" /I "${JAVAINCLUDES}/win32" /I . ${WINDOWS_SOURCES[*]}
EOF

# Invoke the file and hopefully generate the .DLL .
exec "${VSTEMP}/windows_jni.bat"
