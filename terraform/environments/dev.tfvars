# Dev environment variables
environments = {
  dev = {
    namespace     = "dev"
    greeting_name = "Dev-Engineer"
    replica_count = 2
    image_tag     = "test"
    ingress_host  = "dev.greeter.local"
    ingress_path  = "/"
  }
}
