terraform {
  required_providers {
    docker = { source = "docker/docker", version = "0.4.1" }
  }
}
output "helper" { value = "helper" }
