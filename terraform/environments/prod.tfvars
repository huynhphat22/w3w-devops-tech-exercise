# Prod environment variables
environments = {
  prod = {
    namespace     = "prod"
    greeting_name = "Prod-Operations"
    replica_count = 3
    image_tag     = "test"
    ingress_host  = "prod.greeter.local"
    ingress_path  = "/"
  }
}
