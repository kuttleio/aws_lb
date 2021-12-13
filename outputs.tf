output "internal_loadbalancer" {
  value = aws_lb.internal
}


output "public_loadbalancer" {
  value = aws_lb.public
}


output "aws_lb_s3_log_bucket" {
  value = aws_s3_bucket.log_bucket.bucket
}


output "es_tg" {
  value = aws_lb_target_group.es_tg
}
