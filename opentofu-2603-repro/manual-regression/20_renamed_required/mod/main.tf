terraform {
  required_providers {
    alternate = { source = "docker/docker", version = "0.4.1" }
  }
}
output "helper" { value = "helper" }
