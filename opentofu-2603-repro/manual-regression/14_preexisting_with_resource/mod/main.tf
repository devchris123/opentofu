provider "terraform" {}
resource "terraform_data" "check" { input = "ok" }
output "helper" { value = terraform_data.check.output }
