#!/bin/bash
set -o errexit
set -o nounset

IMG="$REGISTRY/$REPOSITORY:$TAG"

# Run image internal tests
docker run -i --rm --entrypoint bats "$IMG" "/tmp/test/$TAG" "/tmp/test"

# Run external tests
./test-restart.sh "$IMG"
./test-replication.sh "$IMG"
./test-replication.sh "$IMG" ssl

echo "#############"
echo "# Tests OK! #"
echo "#############"
