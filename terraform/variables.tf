variable "kubeconfig_path" {
  description = "Path to the kubeconfig file (defaults to ~/.kube/config)"
  type        = string
  default     = ""
}

variable "kubeconfig_context" {
  description = "Specific Kubernetes context to use from kubeconfig (null uses current context)"
  type        = string
  default     = ""
}

variable "environments" {
  description = "Map of environment configurations deploying dev and prod without duplicating code"
  type = map(object({
    namespace        = string
    greeting_name    = string
    replica_count    = number
    image_repository = optional(string, "ghcr.io/huynhphat22/w3w-devops-tech-exercise")
    image_tag        = optional(string, "latest")
    use_local_image  = optional(bool, false)
    ingress_host     = optional(string, "")
    ingress_path     = optional(string, "/")
  }))
  default = {
    dev = {
      namespace        = "dev"
      greeting_name    = "Dev-Engineer"
      replica_count    = 2
      image_repository = "ghcr.io/huynhphat22/w3w-devops-tech-exercise"
      image_tag        = "latest"
      use_local_image  = false
      ingress_host     = "dev.greeter.local"
      ingress_path     = "/"
    }
    prod = {
      namespace        = "prod"
      greeting_name    = "Prod-Operations"
      replica_count    = 3
      image_repository = "ghcr.io/huynhphat22/w3w-devops-tech-exercise"
      image_tag        = "latest"
      use_local_image  = false
      ingress_host     = "prod.greeter.local"
      ingress_path     = "/"
    }
  }
}
