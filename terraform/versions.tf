terraform {
  required_version = ">= 1.5.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.26"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path != "" ? pathexpand(var.kubeconfig_path) : pathexpand("~/.kube/config")
    config_context = var.kubeconfig_context != "" ? var.kubeconfig_context : null
  }
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path != "" ? pathexpand(var.kubeconfig_path) : pathexpand("~/.kube/config")
  config_context = var.kubeconfig_context != "" ? var.kubeconfig_context : null
}
