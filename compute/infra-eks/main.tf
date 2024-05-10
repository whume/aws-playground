locals {
  name = "infra"
}

data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "tf-state-176207359176"
    key    = "networking/terraform.tfstate"
    region = "us-east-1"
  }
}

module "eks" {
  source = "terraform-aws-modules/eks/aws"

  cluster_name    = local.name
  cluster_version = "1.29"

  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true
  cluster_enabled_log_types                = []
  cluster_addons = {
    coredns                = {
      configuration_values = jsonencode({
        computeType = "fargate"
      })
    }
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
  }

  vpc_id                   = data.terraform_remote_state.infra.outputs.infra_vpc_id
  subnet_ids               = data.terraform_remote_state.infra.outputs.infra_private_subnets
  control_plane_subnet_ids = data.terraform_remote_state.infra.outputs.infra_intra_subnets

  authentication_mode       = "API"
  fargate_profiles = {
    karpenter = {
      selectors = [
        { namespace = "karpenter" }
      ]
    }
    kube-system = {
      selectors = [
        { namespace = "kube-system" }
      ]
    }
  }
  tags = {
    "karpenter.sh/discovery" = local.name
  }
}

# Karpenter
module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"

  cluster_name = module.eks.cluster_name

  enable_pod_identity             = false
  create_pod_identity_association = false
  enable_irsa                     =  true
  irsa_oidc_provider_arn          = module.eks.oidc_provider_arn

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}


resource "helm_release" "karpenter" {
  namespace           = "karpenter"
  create_namespace    = true
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = "0.36.1"
  wait                = false
  set {
    name  = "logLevel"
    value = "debug"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.karpenter.iam_role_arn
  }
  values = [
    <<-EOT
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    EOT
  ]
}

resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1beta1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiFamily: AL2
      role: ${module.karpenter.node_iam_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1beta1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        spec:
          nodeClassRef:
            name: default
          requirements:
            - key: "karpenter.k8s.aws/instance-category"
              operator: In
              values: ["t", "m"]
            - key: "karpenter.k8s.aws/instance-hypervisor"
              operator: In
              values: ["nitro"]
            - key: "karpenter.k8s.aws/instance-generation"
              operator: Gt
              values: ["2"]
      limits:
        cpu: 1000
      disruption:
        consolidationPolicy: WhenUnderutilized
  YAML

  depends_on = [
    kubectl_manifest.karpenter_node_class
  ]
}


# Auth
data "aws_iam_role" "admin" {
  name = "AWSReservedSSO_AdministratorAccess_90d5adc5d5249c88"
}

resource "aws_eks_access_entry" "infra_admin" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = data.aws_iam_role.admin.arn
  type              = "STANDARD"
}

resource "aws_eks_access_policy_association" "infra_admin" {
  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = data.aws_iam_role.admin.arn

  access_scope {
    type       = "cluster"
  }
}