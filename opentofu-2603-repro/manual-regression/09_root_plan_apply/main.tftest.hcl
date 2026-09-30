provider "docker" {
  username = "user"
  password = "password"
}
run "root_plan" { command = plan }
run "helper" {
  module {
    source = "./mod"
  }
}
run "root_apply" { command = apply }
