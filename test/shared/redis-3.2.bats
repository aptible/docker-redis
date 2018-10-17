@test "It should install Redis 3.2.12" {
  run redis-server --version
  [[ "$output" =~ "3.2.12"  ]]
}
