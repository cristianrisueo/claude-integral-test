# Network isolation: each component accepts traffic only from the one in front
# of it, and the database has no way out. Mocked provider: no AWS call, no
# credentials. The mock leaves unset rule fields null where AWS returns [] or
# false, so "no other source" accepts both.

mock_provider "aws" {
  source = "./tests/mocks"
}

override_data {
  target = data.aws_ec2_managed_prefix_list.cloudfront
  values = {
    id = "pl-4fa04526"
  }
}

run "database_is_isolated" {
  command = apply

  assert {
    condition     = aws_db_instance.main.publicly_accessible == false
    error_message = "The database must not be publicly accessible."
  }

  assert {
    condition     = aws_db_instance.main.vpc_security_group_ids == toset([aws_security_group.database.id])
    error_message = "The database must use only the database security group."
  }

  assert {
    condition     = length(aws_security_group.database.ingress) == 1
    error_message = "The database security group must have exactly one ingress rule."
  }

  assert {
    condition = alltrue([
      for rule in aws_security_group.database.ingress :
      rule.protocol == "tcp" && rule.from_port == 5432 && rule.to_port == 5432
      && rule.security_groups == toset([aws_security_group.api.id])
      && (rule.cidr_blocks == null || length(rule.cidr_blocks) == 0) && (rule.ipv6_cidr_blocks == null || length(rule.ipv6_cidr_blocks) == 0)
      && (rule.prefix_list_ids == null || length(rule.prefix_list_ids) == 0) && rule.self != true
    ])
    error_message = "The database must accept only the API security group, on TCP 5432."
  }

  assert {
    condition     = aws_db_instance.main.db_subnet_group_name == aws_db_subnet_group.main.name
    error_message = "The database must sit in the database subnet group."
  }

  assert {
    condition     = aws_db_subnet_group.main.subnet_ids == toset([for s in aws_subnet.database : s.id])
    error_message = "The database subnet group must hold exactly the database subnets."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.database : s.map_public_ip_on_launch == false])
    error_message = "The database subnets must not assign public IPs."
  }

  assert {
    condition     = toset([for a in aws_route_table_association.database : a.subnet_id]) == toset([for s in aws_subnet.database : s.id])
    error_message = "Every database subnet must be associated with a route table explicitly."
  }

  assert {
    condition     = alltrue([for a in aws_route_table_association.database : a.route_table_id == aws_route_table.database.id])
    error_message = "The database subnets must use the database route table."
  }

  assert {
    condition     = length(aws_route_table.database.route) == 0
    error_message = "The database route table must have no route (no way to the internet gateway)."
  }

  assert {
    condition     = aws_route.internet.gateway_id == aws_internet_gateway.main.id && aws_route.internet.route_table_id == aws_route_table.public.id
    error_message = "The only route to the internet gateway must belong to the public route table."
  }
}

run "edge_is_isolated" {
  command = apply

  assert {
    condition     = length(aws_security_group.api.ingress) == 1
    error_message = "The API security group must have exactly one ingress rule."
  }

  assert {
    condition = alltrue([
      for rule in aws_security_group.api.ingress :
      rule.protocol == "tcp" && rule.from_port == 8080 && rule.to_port == 8080
      && rule.security_groups == toset([aws_security_group.load_balancer.id])
      && (rule.cidr_blocks == null || length(rule.cidr_blocks) == 0) && (rule.ipv6_cidr_blocks == null || length(rule.ipv6_cidr_blocks) == 0)
      && (rule.prefix_list_ids == null || length(rule.prefix_list_ids) == 0) && rule.self != true
    ])
    error_message = "The API must accept only the load balancer security group, on TCP 8080."
  }

  assert {
    condition     = length(aws_security_group.load_balancer.ingress) == 1
    error_message = "The load balancer security group must have exactly one ingress rule."
  }

  assert {
    condition = alltrue([
      for rule in aws_security_group.load_balancer.ingress :
      rule.prefix_list_ids == tolist(["pl-4fa04526"])
      && (rule.security_groups == null || length(rule.security_groups) == 0)
      && (rule.cidr_blocks == null || length(rule.cidr_blocks) == 0) && (rule.ipv6_cidr_blocks == null || length(rule.ipv6_cidr_blocks) == 0)
      && rule.self != true
    ])
    error_message = "The load balancer must accept only CloudFront's origin-facing prefix list."
  }

  assert {
    condition     = data.aws_ec2_managed_prefix_list.cloudfront.name == "com.amazonaws.global.cloudfront.origin-facing"
    error_message = "The prefix list must be CloudFront's origin-facing one."
  }
}
