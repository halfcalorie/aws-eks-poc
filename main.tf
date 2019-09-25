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

resource "aws_iam_role" "npurkiss_eks" {
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

resource "aws_iam_role_policy_attachment" "demo-cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = "${aws_iam_role.npurkiss_eks.name}"
}

resource "aws_iam_role_policy_attachment" "demo-cluster-AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = "${aws_iam_role.npurkiss_eks.name}"
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
