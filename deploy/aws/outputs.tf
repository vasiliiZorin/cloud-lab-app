output "app_public_ip" {
  value = aws_instance.app.public_ip
}

output "rds_endpoint" {
  value = aws_db_instance.db.address
}

output "redis_endpoint" {
  value = aws_elasticache_cluster.cache.cache_nodes[0].address
}
