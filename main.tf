###############################################################################
# V A R I A B L E S
###############################################################################

provider "aws" {
  region                  = "us-east-1"
  shared_credentials_file = "/Users/npurkiss/.aws/credentials"
  profile                 = "personal"
}
variable "cluster-name" {
  default = "npurkiss_eks"
  type    = "string"
}

variable "kubernetes-version" {
  default = "1.14"
  type    = "string"
}
data "aws_availability_zones" "available" {}


###############################################################################
# V P C
###############################################################################
resource "aws_vpc" "npurkiss_eks_vpc" {
  cidr_block = "192.168.0.0/16"

  tags = "${
    map(
      "Name", "npurkiss_eks",
      "kubernetes.io/cluster/${var.cluster-name}", "shared",
    )
  }"
}
resource "aws_subnet" "npurkiss_eks_subnet" {
  count = 3

  vpc_id            = "${aws_vpc.npurkiss_eks_vpc.id}"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  cidr_block        = "${cidrsubnet(aws_vpc.npurkiss_eks_vpc.cidr_block, 2, count.index)}"

  tags = "${
    map(
      "Name", "npurkiss_eks",
      "kubernetes.io/cluster/${var.cluster-name}", "shared",
    )
  }"
}
resource "aws_internet_gateway" "npurkiss_eks_gateway" {
  vpc_id = "${aws_vpc.npurkiss_eks_vpc.id}"

  tags = {
    Name = "npurkiss_eks"
  }
}

resource "aws_route_table" "npurkiss_eks_route" {
  vpc_id = "${aws_vpc.npurkiss_eks_vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.npurkiss_eks_gateway.id}"
  }
}

resource "aws_route_table_association" "demo" {
  count = 3

  subnet_id      = "${aws_subnet.npurkiss_eks_subnet.*.id[count.index]}"
  route_table_id = "${aws_route_table.npurkiss_eks_route.id}"
}

###############################################################################
#  I A M 
###############################################################################

resource "aws_iam_role" "npurkiss_eks_cluster" {
  name = "npurkiss_eks"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "npurkiss_eks_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = "${aws_iam_role.npurkiss_eks_cluster.name}"
}

resource "aws_iam_role_policy_attachment" "npurkiss_eks_AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = "${aws_iam_role.npurkiss_eks_cluster.name}"
}

resource "aws_iam_role" "npurkiss_eks_node" {
  name = "npurkiss_eks_node"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "npurkiss_eks_node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = "${aws_iam_role.npurkiss_eks_node.name}"
}

resource "aws_iam_role_policy_attachment" "npurkiss_eks_node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = "${aws_iam_role.npurkiss_eks_node.name}"
}

resource "aws_iam_role_policy_attachment" "npurkiss_eks_node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = "${aws_iam_role.npurkiss_eks_node.name}"
}

resource "aws_iam_instance_profile" "npurkiss_eks_node" {
  name = "npurkiss_eks_node"
  role = "${aws_iam_role.npurkiss_eks_node.name}"
}


###############################################################################
# S E C U R I T Y    G R O U P S
###############################################################################
resource "aws_security_group" "npurkiss_eks" {
  name        = "npurkiss_eks"
  description = "Cluster communication with worker nodes"
  vpc_id      = "${aws_vpc.npurkiss_eks_vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "npurkiss_eks"
  }
}

# OPTIONAL: Allow inbound traffic from your local workstation external IP
#           to the Kubernetes. You will need to replace A.B.C.D below with
#           your real IP. Services like icanhazip.com can help you find this.
resource "aws_security_group_rule" "eks-cluster-ingress-workstation-https" {
  cidr_blocks       = ["129.41.86.5/32"]
  description       = "Allow workstation to communicate with the cluster API Server"
  from_port         = 443
  protocol          = "tcp"
  security_group_id = "${aws_security_group.npurkiss_eks.id}"
  to_port           = 443
  type              = "ingress"
}

resource "aws_security_group" "npurkiss_eks_node" {
  name        = "npurkiss_eks_node"
  description = "Security group for all nodes in the cluster"
  vpc_id      = "${aws_vpc.npurkiss_eks_vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${
    map(
     "Name", "npurkiss_eks_node",
     "kubernetes.io/cluster/${var.cluster-name}", "owned",
    )
  }"
}

resource "aws_security_group_rule" "npurkiss_eks_node-ingress-self" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = "${aws_security_group.npurkiss_eks_node.id}"
  source_security_group_id = "${aws_security_group.npurkiss_eks_node.id}"
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "npurkiss_eks_node-ingress-cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.npurkiss_eks_node.id}"
  source_security_group_id = "${aws_security_group.npurkiss_eks_node.id}"
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "npurkiss_eks-ingress-node-https" {
  description              = "Allow pods to communicate with the cluster API Server"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.npurkiss_eks.id}"
  source_security_group_id = "${aws_security_group.npurkiss_eks_node.id}"
  to_port                  = 443
  type                     = "ingress"
}

###############################################################################
# E K S    C L U S T E R (S)
###############################################################################
resource "aws_eks_cluster" "npurkiss_eks" {
  name            = "${var.cluster-name}"
  role_arn        = "${aws_iam_role.npurkiss_eks_cluster.arn}"
  version         = "${var.kubernetes-version}"
  vpc_config {
    security_group_ids = ["${aws_security_group.npurkiss_eks.id}"]
    subnet_ids         = ["${aws_subnet.npurkiss_eks_subnet.*.id}"]
  }

  depends_on = [
    "aws_iam_role_policy_attachment.npurkiss_eks_AmazonEKSClusterPolicy",
    "aws_iam_role_policy_attachment.npurkiss_eks_AmazonEKSServicePolicy",
  ]
}
data "aws_ami" "eks-worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${aws_eks_cluster.npurkiss_eks.version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}

# This data source is included for ease of sample architecture deployment
# and can be swapped out as necessary.
data "aws_region" "current" {}

# EKS currently documents this required userdata for EKS worker nodes to
# properly configure Kubernetes applications on the EC2 instance.
# We implement a Terraform local here to simplify Base64 encoding this
# information into the AutoScaling Launch Configuration.
# # More information: https://docs.aws.amazon.com/eks/latest/userguide/launch-workers.html
locals {
  npurkiss_eks_userdata = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.npurkiss_eks.endpoint}' --b64-cluster-ca '${aws_eks_cluster.npurkiss_eks.certificate_authority.0.data}' '${var.cluster-name}'
USERDATA
}

resource "aws_launch_configuration" "npurkiss_eks_node" {
  associate_public_ip_address = true
  iam_instance_profile        = "${aws_iam_instance_profile.npurkiss_eks_node.name}"
  image_id                    = "${data.aws_ami.eks-worker.id}"
  instance_type               = "m4.large"
  name_prefix                 = "npurkiss_eks"
  security_groups             = ["${aws_security_group.npurkiss_eks_node.id}"]
  user_data_base64            = "${base64encode(local.npurkiss_eks_userdata)}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "npurkiss_eks_nodes" {
  desired_capacity     = 2
  launch_configuration = "${aws_launch_configuration.npurkiss_eks_node.id}"
  max_size             = 2
  min_size             = 1
  name                 = "npurkiss_eks_node"
  vpc_zone_identifier  = ["${aws_subnet.npurkiss_eks_subnet.*.id}"]

  tag {
    key                 = "Name"
    value               = "npurkiss_eks_node"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster-name}"
    value               = "owned"
    propagate_at_launch = true
  }
}

### output an example IAM Role authentication ConfigMap from your Terraform configuration
locals {
  config_map_aws_auth = <<CONFIGMAPAWSAUTH


apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${aws_iam_role.npurkiss_eks_node.arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
CONFIGMAPAWSAUTH
}

output "config_map_aws_auth" {
  value = "${local.config_map_aws_auth}"
}

