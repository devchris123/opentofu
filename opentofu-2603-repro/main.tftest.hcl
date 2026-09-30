provider "docker" {
  username = "user"
  password = "password"
}

run "setup" {
  module {
    source = "./mod"
  }
}
