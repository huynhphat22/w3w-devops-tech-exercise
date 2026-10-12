output "environments" {
  description = "Summary of deployed environments and releases"
  value = {
    for env, mod in module.greeter : env => {
      release_name = mod.release_name
      namespace    = mod.namespace
      ingress_host = var.environments[env].ingress_host
      replicas     = var.environments[env].replica_count
      greeting     = var.environments[env].greeting_name
    }
  }
}
