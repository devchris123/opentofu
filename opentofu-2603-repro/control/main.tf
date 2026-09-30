terraform {
  required_providers {
    docker = {
      source  = "docker/docker"
      version = "0.4.1"
    }
  }
}

data "docker_hub_repository" "example" {
  namespace = "library"
  name      = "memcached"
}
