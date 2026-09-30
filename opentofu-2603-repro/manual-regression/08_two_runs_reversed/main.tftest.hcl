provider "docker" {
  alias = "testing"
  username = "user"
  password = "password"
}
run "first" {
  module {
    source = "./mod"
  }
  providers = { alternate = docker.testing }
}
run "second" {
  module {
    source = "./mod"
  }
  providers = { docker = docker.testing }
}
