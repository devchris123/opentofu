terraform {
  required_providers {
    terraform = { source = "docker/docker", version = "0.4.1" }
  }
}
output "root" { value = "root" }
