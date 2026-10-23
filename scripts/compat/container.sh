#!/bin/sh
# compat/container.sh: run compat/run.sh inside a throwaway Autark system, so `ark install` can build and install a
# package's dependencies for real without touching this one. The system is the release rootfs, imported into rootless
# Docker: no sudo. What is built stays in the container, so a second run starts where the first stopped.
#
#   scripts/compat/container.sh setup         import the rootfs as an image and make the container (once; several GB)
#   scripts/compat/container.sh run [list]    try every package in the list (default: packages.txt); can be stopped and run again
#   scripts/compat/container.sh status        the results so far
#   scripts/compat/container.sh shell         a shell inside, to look at a failure
#   scripts/compat/container.sh reset         delete the container and everything built in it (the image stays)
#
#   ROOTFS=file    the rootfs tarball (default ~/autark-release/autark-rootfs-0.1-test.tar.zst)
#   ARK=file       the ark to run inside it; it needs --make-deps (default: ark on PATH)
#   OUT=dir        where results.tsv and the logs go on this machine (default: ./compat-results)
#   CPUS, MEMORY   limits for the container, so the desktop stays usable (default 6 and 12g)
#   TIMEOUT, KEEP  as for run.sh

set -u
here=$(cd "$(dirname "$0")" && pwd)
REPO=${REPO:-$(dirname "$(dirname "$here")")}
ROOTFS=${ROOTFS:-$HOME/autark-release/autark-rootfs-0.1-test.tar.zst}
ARK=${ARK:-$(command -v ark || true)}
OUT=${OUT:-$PWD/compat-results}
CPUS=${CPUS:-6}
MEMORY=${MEMORY:-12g}
NAME=autark-compat
IMAGE=autark-compat:rootfs
DOCKER_HOST=${DOCKER_HOST:-unix:///run/user/$(id -u)/docker.sock}
export DOCKER_HOST

die() { echo "compat/container.sh: $*" >&2; exit 1; }

command -v docker > /dev/null 2>&1 || die "no docker"
docker info > /dev/null 2>&1 || die "docker isn't running for you (rootless: systemctl --user start docker)"

setup() {
    if ! docker image inspect "$IMAGE" > /dev/null 2>&1; then
        [ -f "$ROOTFS" ] || die "no rootfs at $ROOTFS; set ROOTFS=file"
        echo "importing $ROOTFS: a few minutes, and about 10 GB of disk"
        zstd -dc "$ROOTFS" | docker import --change 'CMD ["sleep","infinity"]' - "$IMAGE" > /dev/null || die "the import failed"
    fi
    if docker container inspect "$NAME" > /dev/null 2>&1; then
        return
    fi
    [ -n "$ARK" ] && [ -f "$ARK" ] || die "no ark to run inside it; set ARK=/path/to/ark"
    mkdir -p "$OUT"
    # --network host: builds need it in rootless Docker. The scripts go in read-only, as root's, like on a real system.
    docker create --name "$NAME" --network host --cpus "$CPUS" --memory "$MEMORY" \
        -v "$REPO/scripts:/usr/src/autark/scripts:ro" -v "$ARK:/usr/local/bin/ark:ro" -v "$OUT:/out" \
        "$IMAGE" > /dev/null || die "couldn't create the container"
    echo "container $NAME is ready"
}

case ${1:-} in
    setup) setup ;;
    run)
        setup
        docker start "$NAME" > /dev/null || die "couldn't start $NAME"
        # The release rootfs has no secret keys, so builds could not sign; this container gets its own throwaway one.
        docker exec "$NAME" sh -c '[ -f /etc/autark/pkg-secret.key ] || /usr/local/bin/ark keygen' > /dev/null || die "couldn't make a signing key"
        if [ -n "${2:-}" ]; then
            # Through the results folder: docker cp can't write into a container that has read-only mounts.
            cp "$2" "$OUT/list.txt" || die "couldn't copy $2"
            list=/out/list.txt
        else
            list=/usr/src/autark/scripts/compat/packages.txt
        fi
        exec docker exec -e ACTION=install -e ARK=/usr/local/bin/ark -e OUT=/out -e "TIMEOUT=${TIMEOUT:-45}" ${KEEP:+-e KEEP=1} \
            "$NAME" sh /usr/src/autark/scripts/compat/run.sh "$list"
        ;;
    status) cat "$OUT/results.tsv" ;;
    shell)
        docker start "$NAME" > /dev/null || die "no container: run setup first"
        exec docker exec -it "$NAME" bash
        ;;
    reset) docker rm -f "$NAME" > /dev/null && echo "removed $NAME; the image $IMAGE stays" ;;
    *) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
