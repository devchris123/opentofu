provider "docker" {
  username = "user"
  password = "password"
}
run "helper" {
  module {
    source = "./mod"
  }
}
