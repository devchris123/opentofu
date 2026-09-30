terraform {
  required_providers {
    docker = { source = "docker/docker", version = "0.4.1" }
    terraform = { source = "docker/docker", version = "0.4.1" }
  }
}
output "root" { value = "root" }
