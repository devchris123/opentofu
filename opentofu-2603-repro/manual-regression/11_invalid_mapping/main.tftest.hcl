provider "docker" {
  username = "user"
  password = "password"
}
run "helper" {
  module {
    source = "./mod"
  }
  providers = { docker = docker.missing }
}
