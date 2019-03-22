@test "It should install Redis 4.0.14" {
  run redis-server --version
  [[ "$output" =~ "4.0.14"  ]]
}
