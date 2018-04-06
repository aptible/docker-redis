@test "It should install Redis 4.0" {
  run redis-server --version
  [[ "$output" =~ "4.0.2"  ]]
}
