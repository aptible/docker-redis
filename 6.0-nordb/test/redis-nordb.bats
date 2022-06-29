source '/tmp/test/test_helper.sh'

setup() {
  do_setup
}

teardown() {
  do_teardown
}

@test "It should disable persistency" {
  initialize_redis

  start_redis
  run-database.sh --client "$REDIS_DATABASE_URL" SET test_key test_value

  stop_redis
  start_redis

  ! run-database.sh --client "$REDIS_DATABASE_URL" GET test_key | grep -q test_value
}
