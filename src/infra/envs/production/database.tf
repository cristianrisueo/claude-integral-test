# PostgreSQL 17 on the smallest instance, one zone. Built to be destroyed in
# one run and re-created right after: no deletion protection, no final
# snapshot, no backups, and a password RDS generates and keeps in a secret of
# its own (random name, deleted with the instance), so nothing collides with a
# secret still pending deletion. TLS is required by the default postgres17
# parameter group (rds.force_ssl = 1).

resource "aws_db_subnet_group" "main" {
  name       = local.name
  subnet_ids = [for s in aws_subnet.database : s.id]
}

resource "aws_db_instance" "main" {
  identifier     = local.name
  engine         = "postgres"
  engine_version = "17"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true # AWS-managed key, never a customer-managed one

  db_name                     = "app"
  username                    = "app"
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  multi_az               = false

  deletion_protection      = false
  skip_final_snapshot      = true
  backup_retention_period  = 0
  delete_automated_backups = true
}
