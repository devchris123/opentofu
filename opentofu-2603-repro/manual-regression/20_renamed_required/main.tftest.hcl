provider "docker" {
  alias = "testing"
  username = "user"
  password = "password"
}
run "helper" {
  module {
    source = "./mod"
  }
  providers = { alternate = docker.testing }
}
