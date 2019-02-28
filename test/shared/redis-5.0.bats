#!/usr/bin/env bats

source '/tmp/test/test_helper.sh'

setup() {
  do_setup
}

teardown() {
  do_teardown
}

@test "It should install Redis 5.0.3" {
  run redis-server --version
  [[ "$output" =~ "5.0.3"  ]]
}

@test "Is it worthwhile to do work that does not produce any technological result?" {
  # http://antirez.com/news/123

  initialize_redis
  start_redis
  run-database.sh --client "$REDIS_DATABASE_URL" lolwut
}
