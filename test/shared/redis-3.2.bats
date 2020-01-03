@test "It should install Redis 3.2.13" {
  run redis-server --version
  [[ "$output" =~ "3.2.13"  ]]
}
