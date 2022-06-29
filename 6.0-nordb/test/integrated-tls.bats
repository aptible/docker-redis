#!/usr/bin/env bats

source '/tmp/test/test_helper.sh'

setup() {
  do_setup
}

teardown() {
  do_teardown
}

@test "server allows TLS1.2" {
  initialize_redis
  start_redis
  run local_s_client "$SSL_PORT" -tls1_2
  [ "$status" -eq 0 ]
}

@test "server disallows TLS1.1" {
  initialize_redis
  start_redis
  run local_s_client "$SSL_PORT" -tls1_1
  [ "$status" -ne 0 ]
}

@test "server disallows TLS1.0" {
  initialize_redis
  start_redis
  run local_s_client "$SSL_PORT" -tls1
  [ "$status" -ne 0 ]
}

@test "server disallows SSLv3" {
  initialize_redis
  start_redis
  run local_s_client "$SSL_PORT" -ssl3
  [ "$status" -ne 0 ]
}
