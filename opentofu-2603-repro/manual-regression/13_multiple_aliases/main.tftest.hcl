provider "docker" {
  alias = "east"
  username = "user"
  password = "password"
}
provider "docker" {
  alias = "west"
  username = "user"
  password = "password"
}
run "helper" {
  module {
    source = "./mod"
  }
  providers = {
    docker.east = docker.east
    docker.west = docker.west
  }
}
