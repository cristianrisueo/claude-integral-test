# The API image registry. Tags are mutable because every deploy re-pushes
# `live`. force_delete lets a destroy remove it with its images inside.

resource "aws_ecr_repository" "api" {
  name                 = "${local.name}-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  encryption_configuration {
    encryption_type = "AES256"
  }
}
