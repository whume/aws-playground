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

data "aws_subnet" "selected" {
  for_each = toset(data.terraform_remote_state.infra.outputs.infra_private_subnets)
  id = each.value
}

locals {
  zone_names          = ["us-east-1a", "us-east-1b"]
  excluded_cidrs      = ["100.64.0.0/16", "100.128.0.0/16"]
  subnet_ids          = [for sid, subnet in data.aws_subnet.selected : sid if !contains(local.excluded_cidrs, subnet.cidr_block)]
  excluded_subnet_ids = [for sid, subnet in data.aws_subnet.selected : sid if contains(local.excluded_cidrs, subnet.cidr_block)]
}

module "eks" {
  source = "terraform-aws-modules/eks/aws"

  cluster_name    = local.name
  cluster_version = "1.29"

  # Needed Setting See: https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/1897
  create_cluster_primary_security_group_tags = false

  enable_cluster_creator_admin_permissions   = true
  cluster_endpoint_public_access             = true
  cluster_enabled_log_types                  = []
  cluster_addons = {
    coredns = {
      configuration_values = jsonencode({
        computeType = "fargate"
      })
    }
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {
      most_recent          = true
      configuration_values = jsonencode({
        env = {
          AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"
          ENI_CONFIG_LABEL_DEF="topology.kubernetes.io/zone"
        }
      })
    }
  }

  vpc_id                   = data.terraform_remote_state.infra.outputs.infra_vpc_id
  subnet_ids               = local.subnet_ids
  control_plane_subnet_ids = data.terraform_remote_state.infra.outputs.infra_intra_subnets

  authentication_mode = "API"
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

# This is to leverage the secondary CIDR's for all nodes and pods
resource "kubectl_manifest" "eks_eni_config" {
  for_each = { for idx, sid in local.excluded_subnet_ids : idx => sid }
  yaml_body = <<-YAML
    apiVersion: crd.k8s.amazonaws.com/v1alpha1
    kind: ENIConfig
    metadata:
      name: ${local.zone_names[each.key]}
    spec:
      securityGroups:
        - ${module.eks.cluster_security_group_id}
      subnet: ${each.value}
  YAML
}

# Karpenter
module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"

  cluster_name = module.eks.cluster_name

  enable_pod_identity             = false
  create_pod_identity_association = false
  enable_irsa                     = true
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
  depends_on = [module.eks.fargate_profiles]
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
data "aws_iam_roles" "roles" {
  name_regex  = "AWSReservedSSO_AdministratorAccess_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

resource "aws_eks_access_entry" "infra_admin" {
  for_each      = { for idx, arn in data.aws_iam_roles.roles.arns : idx => arn }
  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "infra_admin" {
  for_each      = { for idx, arn in data.aws_iam_roles.roles.arns : idx => arn }
  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = each.value
  access_scope {
    type = "cluster"
  }
}

# AWS Load Balancer Controller
module "load_balancer_controller" {
  source = "git::https://github.com/DNXLabs/terraform-aws-eks-lb-controller.git"

  helm_chart_version               = "1.7.2"
  cluster_identity_oidc_issuer     = module.eks.cluster_oidc_issuer_url
  cluster_identity_oidc_issuer_arn = module.eks.oidc_provider_arn
  cluster_name                     = module.eks.cluster_name
  settings = {
    region : "us-east-1"
    vpcId : data.terraform_remote_state.infra.outputs.infra_vpc_id
  }
  depends_on = [module.eks.fargate_profiles]
}