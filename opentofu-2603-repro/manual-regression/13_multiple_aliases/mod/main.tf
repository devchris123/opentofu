terraform {
  required_providers {
    docker = {
      source = "docker/docker"
      version = "0.4.1"
      configuration_aliases = [docker.east, docker.west]
    }
  }
}
output "helper" { value = "helper" }
