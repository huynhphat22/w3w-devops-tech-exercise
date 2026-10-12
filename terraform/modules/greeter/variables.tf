variable "environment" {
  description = "The target deployment environment (e.g., dev, prod)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to deploy the release into"
  type        = string
}

variable "create_namespace" {
  description = "Whether to create the Kubernetes namespace"
  type        = bool
  default     = true
}

variable "greeting_name" {
  description = "The greeting name displayed by the application"
  type        = string
}

variable "replica_count" {
  description = "Number of desired pod replicas for high availability"
  type        = number
  default     = 2
}

variable "image_repository" {
  description = "Container image repository"
  type        = string
  default     = "greeter"
}

variable "image_tag" {
  description = "Container image tag"
  type        = string
  default     = "test"
}

variable "image_pull_policy" {
  description = "Image pull policy (IfNotPresent for local cluster)"
  type        = string
  default     = "IfNotPresent"
}

variable "ingress_enabled" {
  description = "Whether to enable Ingress for external access"
  type        = bool
  default     = true
}

variable "ingress_host" {
  description = "Hostname for Ingress rule (e.g., dev.greeter.local)"
  type        = string
  default     = ""
}

variable "ingress_path" {
  description = "Path for Ingress rule"
  type        = string
  default     = "/"
}
