#!/bin/bash
set -o errexit
set -o nounset

IMG="$1"
SSL_KEY="$(cat test/ssl/server-key.pem)"
SSL_CERT="$(cat test/ssl/server-cert.pem)"
CA_CERT="$(cat test/ssl/ca.pem)"

PROTOCOL="redis"
PORT_VARIABLE="REDIS_PORT"

if [[ "$#" -eq 2 ]]; then
  if [[ "$2" = "ssl" ]]; then
    PROTOCOL="rediss"
    PORT_VARIABLE="SSL_PORT"
  else
    echo "Unknown argument: $2"
    exit 1
  fi
fi

if [[ "$(echo "$REDIS_VERSION" | cut -f1 -d.)" -ge '6' ]]; then
  USERNAME='testuser'
  OPTS=(-e CA_CERTIFICATE="$CA_CERT")
else
  USERNAME=''
  OPTS=(-e DANGER_DISABLE_CERT_VALIDATION=1)
fi

MASTER_CONTAINER="redis-master"
MASTER_DATA_CONTAINER="${MASTER_CONTAINER}-data"
SLAVE_CONTAINER="redis-slave"
SLAVE_DATA_CONTAINER="${SLAVE_CONTAINER}-data"

CLONE_CONTAINER="redis-clone"
CLONE_DATA_CONTAINER="${CLONE_CONTAINER}-data"

FIFO_CONTAINER="redis-fifo"
FIFO_EXPORT="redis-fifo-out"
FIFO_IMPORT="redis-fifo-in"

function cleanup {
  docker rm -f \
    "$MASTER_CONTAINER" "$MASTER_DATA_CONTAINER" \
    "$SLAVE_CONTAINER" "$SLAVE_DATA_CONTAINER" \
    "$CLONE_CONTAINER" "$CLONE_DATA_CONTAINER" \
    "$FIFO_CONTAINER" "$FIFO_EXPORT" "$FIFO_IMPORT" \
    >/dev/null 2>&1 || true
}

trap cleanup EXIT
cleanup

PASSPHRASE=testpass

echo "Running replication test with protocol ${PROTOCOL} and port ${PORT_VARIABLE}"


echo "Initializing data containers"

docker create --name "$MASTER_DATA_CONTAINER" "$IMG"
docker create --name "$SLAVE_DATA_CONTAINER" "$IMG"
docker create --name "$CLONE_DATA_CONTAINER" "$IMG"
docker run --name "$FIFO_CONTAINER" --entrypoint /bin/sh  "$IMG" -c "mkfifo /var/db/fifo"


echo "Initializing master"

docker run -it --rm \
  -e PASSPHRASE="$PASSPHRASE" \
  -e USERNAME="$USERNAME" \
  --volumes-from "$MASTER_DATA_CONTAINER" \
  "${OPTS[@]}" "$IMG" --initialize

MASTER_PORT=63791
docker run -d --name="${MASTER_CONTAINER}" \
  -e "${PORT_VARIABLE}=$MASTER_PORT" \
  -e SSL_KEY="$SSL_KEY" \
  -e SSL_CERTIFICATE="$SSL_CERT" \
  --volumes-from "$MASTER_DATA_CONTAINER" \
  "${IMG}"

MASTER_IP="$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' "$MASTER_CONTAINER")"
MASTER_URL="${PROTOCOL}://${USERNAME}:${PASSPHRASE}@${MASTER_IP}:${MASTER_PORT}"
# Empty arrays are considered unset by some shells.
# "${ARR[@]+"${ARR[@]}"}" prevents the script from exiting due to nounset.
until docker run --rm "${OPTS[@]}" "$IMG" --client "$MASTER_URL" INFO >/dev/null; do sleep 0.5; done

echo "Adding test data"

docker run -it --rm "${OPTS[@]}" "$IMG" --client "$MASTER_URL" SET test_before TEST_DATA

echo "Initializing slave"

# When we initialize via SSL, we'll twist things up a bit by providing broken
# non-SSL URLs in the mix and making sure our Redis image prefers to use the
# (functional) SSL URL.

if [[ "$PROTOCOL" == "rediss" ]]; then
  INITIALIZE_FROM_ARGS=("redis://foo" "$MASTER_URL" "redis://bar")
else
  INITIALIZE_FROM_ARGS=("redis://foo" "$MASTER_URL")
fi

docker run -it --rm \
  -e PASSPHRASE="$PASSPHRASE" \
  -e USERNAME="$USERNAME" \
  -e CA_CERTIFICATE="$CA_CERT" \
  --volumes-from "$SLAVE_DATA_CONTAINER" \
  "${OPTS[@]}" "$IMG" --initialize-from "${INITIALIZE_FROM_ARGS[@]}"

SLAVE_PORT=63792
docker run -d --name "$SLAVE_CONTAINER" \
  -e "${PORT_VARIABLE}=$SLAVE_PORT" \
  -e SSL_KEY="$SSL_KEY" \
  -e SSL_CERTIFICATE="$SSL_CERT" \
  -e CA_CERTIFICATE="$CA_CERT" \
  --volumes-from "$SLAVE_DATA_CONTAINER" \
  "${OPTS[@]}" "$IMG"

#docker exec "$SLAVE_CONTAINER" cp "$CA_CERT_FILE" /usr/local/share/ca-certificates/test_ca.crt
#docker exec "$SLAVE_CONTAINER" update-ca-certificates

SLAVE_IP="$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' "$SLAVE_CONTAINER")"
SLAVE_URL="${PROTOCOL}://${USERNAME}:${PASSPHRASE}@${SLAVE_IP}:${SLAVE_PORT}"
until docker run --rm "${OPTS[@]}" "$IMG" --client "$SLAVE_URL" INFO >/dev/null; do sleep 0.5; done

echo "Adding test data"

docker run -it --rm "${OPTS[@]}" "$IMG" --client "$MASTER_URL" SET test_after TEST_DATA

echo "Checking test data"

# Give the test data a moment to show up.
RETRY_TIMES=30

wait_for_key() {
  for i in $(seq "$RETRY_TIMES"); do
    docker run -it --rm "${OPTS[@]}" "$IMG" --client "$SLAVE_URL" GET "$1" | grep "$2" && return 0
    sleep 0.5
  done

  echo "$1 data not found"
  return 1
}

wait_for_key test_before "TEST_DATA"
wait_for_key test_after "TEST_DATA"

echo "Replication test OK!"


if [[ "$(echo "$REDIS_VERSION" | cut -f1 -d.)" -ge 7 ]]; then
  echo "Redis 7+ does not support dump and restore. Skipping clone test."
  exit
fi

echo "Creating empty clone"

docker run -it --rm \
  -e PASSPHRASE="$PASSPHRASE" \
  -e USERNAME="$USERNAME" \
  --volumes-from "$CLONE_DATA_CONTAINER" \
  "${OPTS[@]}" "$IMG" --initialize

CLONE_PORT=63793
docker run -d --name="${CLONE_CONTAINER}" \
  -e "${PORT_VARIABLE}=$CLONE_PORT" \
  -e SSL_KEY="$SSL_KEY" \
  -e SSL_CERTIFICATE="$SSL_CERT" \
  --volumes-from "$CLONE_DATA_CONTAINER" \
  "${IMG}"

CLONE_IP="$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' "$CLONE_CONTAINER")"
CLONE_URL="${PROTOCOL}://${USERNAME}:${PASSPHRASE}@${CLONE_IP}:${CLONE_PORT}"
until docker run --rm "${OPTS[@]}" "$IMG" --client "$CLONE_URL" INFO >/dev/null; do sleep 0.5; done


echo "Checking master has no data"
docker run -it --rm "${OPTS[@]}" "$IMG" --client "$CLONE_URL" --cacert GET test_after | grep "TEST_DATA" && false


echo "Cloning master"

docker run --name "$FIFO_EXPORT" -d \
  --volumes-from "${FIFO_CONTAINER}" \
  --entrypoint "/bin/sh" \
  "${OPTS[@]}" "$IMG" "-c" "ln -s '/var/db/fifo' '/dump-output' && run-database.sh --dump '$MASTER_URL'"

docker run --name "$FIFO_IMPORT" -it \
  --volumes-from "${FIFO_CONTAINER}" \
  --entrypoint "/bin/sh" \
  "${OPTS[@]}" "$IMG" "-c" "ln -s '/var/db/fifo' '/restore-input' && run-database.sh --restore '$CLONE_URL'"

docker run -it --rm "${OPTS[@]}" "$IMG" --client "$CLONE_URL" GET test_after | grep "TEST_DATA"


echo "Clone test OK!"
