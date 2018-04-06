TEST_BASE_DIRECTORY="/tmp/test-root"
TEST_ROOT="/tmp/test"

do_setup() {
  # Create a temporary dir structure for the test
  export DATA_DIRECTORY="${TEST_BASE_DIRECTORY}/data"
  export CONFIG_DIRECTORY="${TEST_BASE_DIRECTORY}/config"
  export STUNNEL_ROOT_DIRECTORY="${TEST_BASE_DIRECTORY}/stunnel"
  export SSL_CERTS_DIRECTORY="${TEST_BASE_DIRECTORY}/certs"
  mkdir -p "$DATA_DIRECTORY" "$CONFIG_DIRECTORY" "$STUNNEL_ROOT_DIRECTORY" "$SSL_CERTS_DIRECTORY"

  # Now, pick different ports to check that our image will accept those
  export REDIS_PORT="$(pick-free-port)"
  export SSL_PORT="$(pick-free-port)"

  if [[ "$REDIS_PORT" = "$SSL_PORT" ]]; then
    echo "Test precondition failed! REDIS_PORT = SSL_PORT = $REDIS_PORT"
    exit 1
  fi

  # Load our test CA as a trusted CA.
  cp "${TEST_ROOT}/ssl/ca.pem" "$SSL_CERTS_DIRECTORY"
  c_rehash "$SSL_CERTS_DIRECTORY"

  # Load our test certs
  export SSL_CERTIFICATE="$(cat "${TEST_ROOT}/ssl/server-cert.pem")"
  export SSL_KEY="$(cat "${TEST_ROOT}/ssl/server-key.pem")"

  export DATABASE_PASSWORD="password12345"

  export REDIS_DATABASE_URL="redis://:$DATABASE_PASSWORD@localhost"
  export REDIS_DATABASE_URL_FULL="redis://:$DATABASE_PASSWORD@localhost:${REDIS_PORT}"

  export SSL_DATABASE_URL="rediss://:$DATABASE_PASSWORD@localhost"
  export SSL_DATABASE_URL_FULL="rediss://:$DATABASE_PASSWORD@localhost:${SSL_PORT}"

  rm -rf "$DATA_DIRECTORY"
  mkdir -p "$DATA_DIRECTORY"
  rm -rf "$CONFIG_DIRECTORY"
  mkdir -p "$CONFIG_DIRECTORY"
}

do_teardown() {
  unset REDIS_DATABASE_URL
  stop_redis
  rm -r "$TEST_BASE_DIRECTORY"
}

initialize_redis () {
  PASSPHRASE="$DATABASE_PASSWORD" run-database.sh --initialize
}

start_redis () {
  run-database.sh > "$TEST_BASE_DIRECTORY/redis.log" 2>&1 &
  timeout 4 sh -c "while  ! grep -q 'accept connections' '$TEST_BASE_DIRECTORY/redis.log' ; do sleep 0.1; done"
}

stop_redis () {
  PID="$(pidof supervisord)" || return 0
  kill -TERM "$PID"
  while [ -n "$PID" ] && [ -e "/proc/${PID}" ]; do sleep 0.1; done
}
