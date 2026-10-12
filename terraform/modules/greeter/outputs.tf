output "release_name" {
  description = "Name of the deployed Helm release"
  value       = helm_release.greeter.name
}

output "namespace" {
  description = "Namespace where the release is deployed"
  value       = helm_release.greeter.namespace
}

output "chart_version" {
  description = "Version of the deployed chart"
  value       = helm_release.greeter.version
}
