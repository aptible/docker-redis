@test "It should install Redis 2.8" {
  run redis-server --version
  [[ "$output" =~ "2.8.24"  ]]
}
