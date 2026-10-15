#!/bin/sh
# protobuf's gate, run before every merge to dev:
#
#   1. every member's tests: the runtime's, the schema reader's and the generator's, with protoc as the
#      oracle for both the encoding and the parse, and the corpus generated into a program of its own
#      that is built and run;
#   2. the runtime built for every freestanding CPU family through tools/portable, which encodes into
#      a stack buffer, generated message included: anything that needs an operating system fails here;
#   3. the protoc-sysl command built.

set -u
root=$(cd "$(dirname "$0")/.." && pwd)
compiler=${PROTOBUF_SYSL:-sysl}
failed=0

step() {
    echo "== $*"
    if ! "$@"; then
        echo "FAIL: $*"
        failed=1
    fi
}

step "$compiler" test "$root"
mkdir -p "$root/scratch"
for target in thumbv6m-freestanding thumbv7em-freestanding thumb-freestanding riscv32-freestanding aarch64-freestanding; do
    step "$compiler" build-c "$root/tools/portable" --target "$target" -o "$root/scratch/portable-$target.a"
done
step "$compiler" build "$root/tools/protoc-sysl" -o "$root/scratch/protoc-sysl"

if [ "$failed" -eq 0 ]; then echo "GATE: green"; else echo "GATE: red"; fi
exit $failed
