# A VPC in two zones and no NAT gateway. The API runs in the public subnets
# but accepts only the load balancer; the database subnets have no route at
# all, so the database cannot reach or be reached from the internet.
#
# Security group rules are inline on purpose: each group's rules are then the
# complete set, so nothing else can open it, and the tests can check "only".

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = local.name }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = local.name }
}

# --- Public subnets: the load balancer and the API tasks --------------------

resource "aws_subnet" "public" {
  for_each = local.zones

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.value
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, index(keys(local.zones), each.key))
  map_public_ip_on_launch = true

  tags = { Name = "${local.name}-public-${each.key}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name}-public" }
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# --- Database subnets: no route out -----------------------------------------

resource "aws_subnet" "database" {
  for_each = local.zones

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.value
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, 10 + index(keys(local.zones), each.key))
  map_public_ip_on_launch = false

  tags = { Name = "${local.name}-database-${each.key}" }
}

# route = [] makes Terraform keep this table empty: only the implicit local
# route remains, and any route added by hand is removed on the next apply.
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id
  route  = []

  tags = { Name = "${local.name}-database" }
}

resource "aws_route_table_association" "database" {
  for_each = aws_subnet.database

  subnet_id      = each.value.id
  route_table_id = aws_route_table.database.id
}

# --- Security groups --------------------------------------------------------

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "load_balancer" {
  name        = "${local.name}-load-balancer"
  description = "Load balancer: HTTP from CloudFront only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from CloudFront origin-facing servers"
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  # The VPC CIDR rather than the API group, to avoid a cycle between groups.
  egress {
    description = "API tasks"
    protocol    = "tcp"
    from_port   = 8080
    to_port     = 8080
    cidr_blocks = [aws_vpc.main.cidr_block]
  }
}

resource "aws_security_group" "api" {
  name        = "${local.name}-api"
  description = "API tasks: port 8080 from the load balancer only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from the load balancer"
    protocol        = "tcp"
    from_port       = 8080
    to_port         = 8080
    security_groups = [aws_security_group.load_balancer.id]
  }

  # Open egress: with no NAT gateway the tasks pull from ECR and write logs
  # through the internet gateway, and reach the database inside the VPC.
  egress {
    description = "All outbound"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "database" {
  name        = "${local.name}-database"
  description = "Database: PostgreSQL from the API tasks only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from the API tasks"
    protocol        = "tcp"
    from_port       = 5432
    to_port         = 5432
    security_groups = [aws_security_group.api.id]
  }
}
