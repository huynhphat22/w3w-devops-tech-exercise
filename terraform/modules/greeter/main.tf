resource "kubernetes_namespace" "env" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "environment"                  = var.environment
    }
  }
}

resource "helm_release" "greeter" {
  name      = "greeter-${var.environment}"
  namespace = var.create_namespace ? kubernetes_namespace.env[0].metadata[0].name : var.namespace
  chart     = "${path.module}/../../../charts/greeter"

  wait    = true
  timeout = 300

  values = [
    yamlencode({
      greetingName = var.greeting_name
      replicaCount = var.replica_count
      image = {
        repository = var.image_repository
        tag        = var.image_tag
        pullPolicy = var.image_pull_policy
        useLocal   = var.use_local_image
      }
      ingress = {
        enabled  = var.ingress_enabled
        host     = var.ingress_host
        path     = var.ingress_path
        pathType = "Prefix"
      }
    })
  ]
}
