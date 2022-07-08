source '/tmp/test/test_helper.sh'

setup() {
  do_setup
}

teardown() {
  do_teardown
}

@test "It should enable persistency" {
  initialize_redis

  start_redis
  run-database.sh --client "$REDIS_DATABASE_URL" SET test_key test_value

  stop_redis

  find / -name '*.rdb'

  [[ -f "${DATA_DIRECTORY}/dump.rdb" ]]

  if [[ "$TAG" =~ .*-aof ]]; then
    # Redis 7 introduced a multi part AOF mechanism
    if [[ "$(echo "$REDIS_VERSION" | cut -f1 -d.)" -ge 7 ]]; then
      [[ -d "${DATA_DIRECTORY}/appendonlydir" ]]
    else
      [[ -f "${DATA_DIRECTORY}/appendonly.aof" ]]
    fi
  else
    [[ ! -f "${DATA_DIRECTORY}/appendonly.aof" ]]
  fi

  start_redis

  run-database.sh --client "$REDIS_DATABASE_URL" GET test_key | grep -q test_value

}
