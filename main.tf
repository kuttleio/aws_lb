##########################################
############### Data Block ###############
##########################################

data "aws_elb_service_account" "main" {}


####################################################
############### S3 Bucket and Policy ###############
####################################################

resource "aws_s3_bucket" "log_bucket" {
  bucket        = "${var.name_prefix}-lb-bucket-log"
  acl           = "private"
  force_destroy = true
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = var.standard_tags
}

resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.log_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.log_bucket.id

  policy = <<POLICY
{
  "Id": "LogBucketPolicy",
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:PutObject"
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:s3:::${aws_s3_bucket.log_bucket.id}/*",
      "Principal": {
        "AWS": [
          "${data.aws_elb_service_account.main.arn}"
        ]
      }
    }
  ]
}
POLICY
}



###################################
############### LB ################
###################################

resource "aws_lb" "internal" {
  name               = "${var.name_prefix}-Internal-LB"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [var.es_lb_sg]
  subnets            = var.es_lb_subnet

  access_logs {
    bucket  = aws_s3_bucket.log_bucket.bucket
    prefix  = "es_lb-lb"
    enabled = true
  }

  tags = merge(
    var.standard_tags,
    tomap({"Name" = "Internal"})
  )

}

resource "aws_lb" "internal_arango" {
  name               = "${var.name_prefix}-Arango-Internal-LB"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [var.es_lb_sg]
  subnets            = var.es_lb_subnet
  idle_timeout       = 1800

  access_logs {
    bucket  = aws_s3_bucket.log_bucket.bucket
    prefix  = "arango_lb-lb"
    enabled = true
  }

  tags = merge(
    var.standard_tags,
    tomap({"Name" = "Arango-Internal"})
  )

}

resource "aws_lb" "public" {
  name               = "${var.name_prefix}-Public-LB"
  load_balancer_type = "application"
  security_groups    = [var.alb_sg]
  subnets            = var.alb_subnet

  access_logs {
    bucket  = aws_s3_bucket.log_bucket.bucket
    prefix  = "leela_lb-lb"
    enabled = true
  }

  tags = merge(
    var.standard_tags,
    tomap({"Name" = "Public"})
  )

}


#############################################
############### LB Listeners ################
#############################################

resource "aws_lb_listener" "public" {
  load_balancer_arn = aws_lb.public.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}


resource "aws_lb_listener" "es_internal" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 9443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-Ext-2018-06"
  certificate_arn   = var.internal_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.es_tg.arn
  }
}
#############################################
############### Target Groups ###############
#############################################


resource "aws_lb_target_group" "es_tg" {
  name                          = "${var.name_prefix}-es-tg" # tg == target-group name is limited to 32 chars
  port                          = var.es_tg_port
  protocol                      = "HTTP"
  vpc_id                        = var.vpc
  load_balancing_algorithm_type = "round_robin"
  target_type                   = "ip"
  depends_on                    = [aws_lb.internal]
}


