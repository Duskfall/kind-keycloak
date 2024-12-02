terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.2.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.9.0"
    }
  }
}

provider "kind" {}

# Create Kind cluster
resource "kind_cluster" "istio_cluster" {
  name            = "istio-cluster-1"  # Changed cluster name
  wait_for_ready  = true
  node_image      = "kindest/node:v1.27.3"

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    networking {
      api_server_address = "127.0.0.1"
      api_server_port    = 0
    }

    node {
      role = "control-plane"
      extra_port_mappings {
        container_port = 30000
        host_port      = 30000
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 30001
        host_port      = 30001
        protocol       = "TCP"
      }
    }

    node {
      role = "worker"
    }
  }
}

provider "kubectl" {
  config_path = kind_cluster.istio_cluster.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = kind_cluster.istio_cluster.kubeconfig_path
  }
}

# Create necessary namespaces
resource "kubectl_manifest" "namespace_istio" {
  yaml_body = <<-EOF
    apiVersion: v1
    kind: Namespace
    metadata:
      name: istio-system
  EOF
  depends_on = [kind_cluster.istio_cluster]
}

resource "kubectl_manifest" "namespace_bookinfo" {
  yaml_body = <<-EOF
    apiVersion: v1
    kind: Namespace
    metadata:
      name: bookinfo
      labels:
        istio-injection: enabled
  EOF
  depends_on = [kind_cluster.istio_cluster]
}

# Install Istio using Helm
resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  namespace        = "istio-system"
  version          = "1.20.0"
  create_namespace = false
  timeout          = 900

  depends_on = [kubectl_manifest.namespace_istio]
}

resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  namespace  = "istio-system"
  version    = "1.20.0"
  timeout    = 900

  depends_on = [helm_release.istio_base]
}

# Install Istio Ingress Gateway
resource "helm_release" "istio_ingress" {
  name       = "istio-ingressgateway"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  namespace  = "istio-system"
  version    = "1.20.0"
  timeout    = 900

  set {
    name  = "service.type"
    value = "NodePort"
  }

  set {
    name  = "service.ports[0].name"
    value = "http2"
  }

  set {
    name  = "service.ports[0].port"
    value = "80"
  }

  set {
    name  = "service.ports[0].targetPort"
    value = "80"
  }

  set {
    name  = "service.ports[0].nodePort"
    value = "30000"
  }

  set {
    name  = "service.ports[1].name"
    value = "https"
  }

  set {
    name  = "service.ports[1].port"
    value = "443"
  }

  set {
    name  = "service.ports[1].targetPort"
    value = "443"
  }

  set {
    name  = "service.ports[1].nodePort"
    value = "30001"
  }

  depends_on = [helm_release.istiod]
}
output "bookinfo_raw_content" {
  value = file("${path.module}/bookinfo.yaml")
  sensitive = true
}
output "bookinfo_split_debug" {
  value = [
    for idx, doc in toset(split("---\n", file("${path.module}/bookinfo.yaml"))) : 
    "${idx}: ${substr(doc, 0, 50)}..."  # Show first 50 chars of each document
  ]
}
# Deploy Bookinfo application
resource "kubectl_manifest" "bookinfo_manifests" {
  for_each = {
    for idx, doc in compact(split("---", file("${path.module}/bookinfo.yaml"))) : 
    idx => doc if trimspace(doc) != ""
  }
  yaml_body = each.value

  depends_on = [
    kubectl_manifest.namespace_bookinfo,
    helm_release.istiod
  ]
}

# Gateway and Virtual Service for Bookinfo
resource "kubectl_manifest" "bookinfo_gateway" {
  yaml_body = <<-EOF
    apiVersion: networking.istio.io/v1alpha3
    kind: Gateway
    metadata:
      name: bookinfo-gateway
      namespace: bookinfo
    spec:
      selector:
        istio: ingressgateway
      servers:
      - port:
          number: 80
          name: http
          protocol: HTTP
        hosts:
        - "*"
  EOF

  depends_on = [
    kubectl_manifest.bookinfo_manifests,
    helm_release.istio_ingress
  ]
}

resource "kubectl_manifest" "bookinfo_virtualservice" {
  yaml_body = <<-EOF
    apiVersion: networking.istio.io/v1alpha3
    kind: VirtualService
    metadata:
      name: bookinfo
      namespace: bookinfo
    spec:
      hosts:
      - "*"
      gateways:
      - bookinfo-gateway
      http:
      - match:
        - uri:
            exact: /productpage
        - uri:
            prefix: /static
        - uri:
            exact: /login
        - uri:
            exact: /logout
        - uri:
            prefix: /api/v1/products
        route:
        - destination:
            host: productpage
            port:
              number: 9080
  EOF

  depends_on = [kubectl_manifest.bookinfo_gateway]
}

# Add Keycloak namespace
resource "kubectl_manifest" "namespace_keycloak" {
  yaml_body = <<-EOF
    apiVersion: v1
    kind: Namespace
    metadata:
      name: keycloak
  EOF
  depends_on = [kind_cluster.istio_cluster]
}

# Add Keycloak Helm repository
resource "helm_release" "keycloak" {
  name       = "keycloak"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "keycloak"
  namespace  = "keycloak"
  version          = "17.3.6"  # Updated to a known stable version
  create_namespace = true
  timeout          = 900  # Increased timeout to 15 minutes
  wait             = true

  set {
    name  = "auth.adminUser"
    value = "admin"
  }

  set {
    name  = "auth.adminPassword"
    value = "admin123"
  }

  set {
    name  = "service.type"
    value = "NodePort"
  }

  set {
    name  = "service.nodePorts.http"
    value = "30002"
  }

  depends_on = [kubectl_manifest.namespace_keycloak]
}

# Configure RequestAuthentication for Istio
resource "kubectl_manifest" "request_authentication" {
  yaml_body = <<-EOF
    apiVersion: security.istio.io/v1beta1
    kind: RequestAuthentication
    metadata:
      name: jwt-auth
      namespace: bookinfo
    spec:
      selector:
        matchLabels:
          app: productpage
      jwtRules:
      - issuer: "http://localhost:30002/realms/bookinfo"
        jwksUri: "http://keycloak.keycloak.svc.cluster.local:80/realms/bookinfo/protocol/openid-connect/certs"
        forwardOriginalToken: true
  EOF
  depends_on = [helm_release.keycloak, kubectl_manifest.bookinfo_manifests]
}


# Configure AuthorizationPolicy
resource "kubectl_manifest" "authorization_policy" {
  yaml_body = <<-EOF
    apiVersion: security.istio.io/v1beta1
    kind: AuthorizationPolicy
    metadata:
      name: require-jwt
      namespace: bookinfo
    spec:
      selector:
        matchLabels:
          app: productpage
      action: ALLOW
      rules:
      - {}  # Empty rule to allow all traffic during testing
  EOF
  depends_on = [kubectl_manifest.request_authentication]
}