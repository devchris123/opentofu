provider "docker" {
  alias = "good"
  username = "user"
  password = "password"
}
provider "docker" {
  alias = "bad"
  invalid_setting = true
}
run "helper" {
  module {
    source = "./mod"
  }
  providers = { docker = docker.good }
}
