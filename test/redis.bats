#!/usr/bin/env bats

@test "It should install Redis " {
  run redis-server --version
  [[ "$output" =~ "2.8.17"  ]]
}

@test "It should install Redis to /usr/bin/redis-server" {
  test -x /usr/bin/redis-server
}
