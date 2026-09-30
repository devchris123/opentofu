mock_provider "docker" {}
run "helper" {
  module {
    source = "./mod"
  }
}
