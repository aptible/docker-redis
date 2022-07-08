#!/usr/bin/env bats

source '/tmp/test/test_helper.sh'

setup() {
  do_setup
}

teardown() {
  do_teardown
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
