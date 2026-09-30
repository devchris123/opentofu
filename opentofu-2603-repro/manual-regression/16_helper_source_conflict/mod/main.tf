terraform {
  required_providers {
    docker = { source = "terraform.io/builtin/terraform" }
  }
}
output "helper" { value = "helper" }
