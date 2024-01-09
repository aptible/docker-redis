#!/usr/bin/env bats

source '/tmp/test/test_helper.sh'

setup() {
  do_setup
}

teardown() {
  do_teardown
}

@test "It should install Redis 7.0.15" {
  run redis-server --version
  [[ "$output" =~ "7.0.15"  ]]
}

@test "Is it worthwhile to do work that does not produce any technological result?" {
  # http://antirez.com/news/123

  initialize_redis
  start_redis
  run-database.sh --client "$REDIS_DATABASE_URL" lolwut
}
