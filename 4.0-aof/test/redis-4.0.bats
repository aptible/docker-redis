@test "It should install Redis 4.0.11" {
  run redis-server --version
  [[ "$output" =~ "4.0.11"  ]]
}
