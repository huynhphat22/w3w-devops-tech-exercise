# Deploy environments via reusable module to avoid duplicating configuration
module "greeter" {
  for_each = var.environments

  source        = "./modules/greeter"
  environment   = each.key
  namespace     = each.value.namespace
  greeting_name = each.value.greeting_name
  replica_count = each.value.replica_count
  image_tag     = each.value.image_tag
  ingress_host  = each.value.ingress_host
  ingress_path  = each.value.ingress_path
}
