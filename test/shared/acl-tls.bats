#!/usr/bin/env bats

source '/tmp/test/test_helper.sh'

setup() {
  do_setup
}

teardown() {
  do_teardown
}

@test "It allows ACLs to be saved" {
  user='acl_user'
  pass='acl_pass'

  initialize_redis
  start_redis

  run-database.sh --client "$REDIS_DATABASE_URL" ACL SETUSER "$user" on ">${pass}" '+@all'
  run-database.sh --client "$REDIS_DATABASE_URL" ACL SAVE

  stop_redis
  start_redis

  run run-database.sh --client "$REDIS_DATABASE_URL" AUTH "$user" "$pass"
  [ "$status" -eq 0 ]
  [[ "$output" =~ 'OK' ]]
}

@test "It allows TLS1.2" {
  initialize_redis
  start_redis
  run local_s_client "$SSL_PORT" -tls1_2
  [ "$status" -eq 0 ]
}

@test "It disallows TLS1.1" {
  initialize_redis
  start_redis
  run local_s_client "$SSL_PORT" -tls1_1
  [ "$status" -ne 0 ]
}

@test "It disallows TLS1.0" {
  initialize_redis
  start_redis
  run local_s_client "$SSL_PORT" -tls1
  [ "$status" -ne 0 ]
}

@test "It disallows SSLv3" {
  initialize_redis
  start_redis
  run local_s_client "$SSL_PORT" -ssl3
  [ "$status" -ne 0 ]
}
