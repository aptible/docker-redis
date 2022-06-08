#!/usr/bin/env bats

source '/tmp/test/test_helper.sh'

setup() {
  do_setup
}

teardown() {
  do_teardown
}

local_s_client() {
  echo OK | openssl s_client -connect localhost:"$@"
}

@test "It should install Redis to /usr/local/bin/redis-server" {
  test -x /usr/local/bin/redis-server
}

@test "It should support Redis connections" {
  initialize_redis
  start_redis
  run-database.sh --client "$REDIS_DATABASE_URL" SET test_key test_value
  run run-database.sh --client "$REDIS_DATABASE_URL_FULL" GET test_key
  [ "$status" -eq "0" ]
  [[ "$output" =~ "test_value" ]]
}

@test "It should require authentication" {
  initialize_redis
  start_redis
  run-database.sh --client "redis://localhost:${REDIS_PORT}/db" INFO 2>&1 | grep NOAUTH
}

@test "It should support SSL connections" {
  initialize_redis
  start_redis
  run-database.sh --client "$SSL_DATABASE_URL" SET test_key test_value
  run run-database.sh --client "$SSL_DATABASE_URL_FULL" GET test_key
  [ "$status" -eq "0" ]
  [[ "$output" =~ "test_value" ]]
}

@test "It should not run two Redis instances" {
  initialize_redis
  start_redis
  run-database.sh --client "$REDIS_DATABASE_URL" SET test_key test_value
  run run-database.sh --client "$SSL_DATABASE_URL" GET test_key
  [ "$status" -eq "0" ]
  [[ "$output" =~ "test_value" ]]
}

@test "It should require SSL on the SSL port" {
  initialize_redis
  start_redis
  run run-database.sh --client "redis://:$DATABASE_PASSWORD@localhost:${SSL_PORT}/db" INFO
  [[ "$status" -eq 1 ]]
}

backup_restore_test() {
  local url="$1"

  run-database.sh --client "$url" SET test_key test_value
  run-database.sh --dump "$url" > redis.dump
  stop_redis

  # Drop ALL the data!!!
  rm -rf "$DATA_DIRECTORY"
  mkdir "$DATA_DIRECTORY"

  # Restart. Data should be gone.
  initialize_redis
  start_redis
  run run-database.sh --client "$url" GET test_key
  [ "$status" -eq "0" ]
  [[ "$output" = "" ]] || \
    [[ "$output" = "Warning: Using a password with '-a' option on the command line interface may not be safe." ]] || \
    [[ "$output" = "Warning: Using a password with '-a' or '-u' option on the command line interface may not be safe." ]]

  # Restore. Data should be back.
  run-database.sh --restore "$url" < redis.dump
  run run-database.sh --client "$url" GET test_key
  [ "$status" -eq "0" ]
  [[ "$output" =~ "test_value" ]]
}

@test "It should backup and restore over the Redis protocol" {
  # Load a key
  initialize_redis
  start_redis
  backup_restore_test "$REDIS_DATABASE_URL"
}

@test "It should backup and restore over SSL" {
  # Load a key
  initialize_redis
  start_redis
  backup_restore_test "$SSL_DATABASE_URL"
}

export_exposed_ports() {
  REDIS_PORT_VAR="EXPOSE_PORT_$REDIS_PORT"
  export $REDIS_PORT_VAR=$REDIS_PORT

  SSL_PORT_VAR="EXPOSE_PORT_$SSL_PORT"
  export $SSL_PORT_VAR=$SSL_PORT
}

@test "It should return valid JSON for --discover and --connection-url" {
  run-database.sh --discover | python -c 'import sys, json; json.load(sys.stdin)'

  # We pretend that both ports are exposed. Depending on the image, only one will be used.
  # We separately test that the port makes sense.
  export_exposed_ports
  EXPOSE_HOST=localhost PASSPHRASE="$DATABASE_PASSWORD" DATABASE=db \
    run-database.sh --connection-url | python -c 'import sys, json; json.load(sys.stdin)'
}

@test "It should return a usable connection URL for --connection-url" {
  initialize_redis
  start_redis

  export_exposed_ports
  EXPOSE_HOST=localhost PASSPHRASE="$DATABASE_PASSWORD" DATABASE=db \
    run-database.sh --connection-url > "${TEST_BASE_DIRECTORY}/url"

  pushd "${TEST_BASE_DIRECTORY}"
  URL="$(python -c "import sys, json; print json.load(open('url'))['credentials'][0]['connection_url']")"
  popd

  [[ "$REDIS_DATABASE_URL_FULL" = "$URL" ]]
  run-database.sh --client "$URL" INFO

  pushd "${TEST_BASE_DIRECTORY}"
  URL="$(python -c "import sys, json; print json.load(open('url'))['credentials'][1]['connection_url']")"
  popd

  [[ "$SSL_DATABASE_URL_FULL" = "$URL" ]]
  run-database.sh --client "$URL" INFO
}

@test "stunnel allows TLS1.2" {
  initialize_redis
  start_redis
  run local_s_client "$SSL_PORT" -tls1_2
  [ "$status" -eq 0 ]
}

@test "stunnel allows TLS1.1" {
  initialize_redis
  start_redis
  run local_s_client "$SSL_PORT" -tls1_1
  [ "$status" -eq 0 ]
}

@test "stunnel allows TLS1.0" {
  initialize_redis
  start_redis
  run local_s_client "$SSL_PORT" -tls1
  [ "$status" -eq 0 ]
}

@test "stunnel disallows SSLv3" {
  initialize_redis
  start_redis
  run local_s_client "$SSL_PORT" -ssl3
  [ "$status" -ne 0 ]
}


@test "It should stop supervisor when Redis dies" {
  if [[ -n "$INTEGRATED_TLS" ]]; then
    skip
  fi

  initialize_redis
  start_redis

  SUPERVISOR_PID="$(pidof supervisord)"

  # If we don't sleep here, the supervisor process state
  # ends up being BACKOFF, and Redis restarts instead of
  # exiting (which is what we monitor for).
  # Multiple BACKOFFs eventually cause supervisor
  # to stop, so we don't care about acting on those.
  # By sleeping, we avoid restarting too quickly, avoiding
  # the BACKOFF status.
  sleep 10

  PID="$(pidof redis-server)"
  pkill -TERM redis-server
  while [ -n "$PID" ] && [ -e "/proc/${PID}" ]; do sleep 0.1; done

  # Supervisor takes a few seconds to stop
  for _ in $(seq 1 30); do
    if [ ! -e "/proc/${SUPERVISOR_PID}" ]; then
      break
    fi
    sleep 1
  done

  run pidof supervisord
  [ "$status" -eq 1 ]
}

@test "It prints the persistent configuration changes on boot." {
  echo "maxclients 12345" >> "${CONFIG_DIRECTORY}/redis.extra.conf"
  initialize_redis
  start_redis

  grep "persistent configuration changes" "${TEST_BASE_DIRECTORY}/redis.log"
  grep "maxclients" "${TEST_BASE_DIRECTORY}/redis.log"
}
