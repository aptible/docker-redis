@test "It should install Redis 3.2" {
  run redis-server --version
  [[ "$output" =~ "3.2.11"  ]]
}
