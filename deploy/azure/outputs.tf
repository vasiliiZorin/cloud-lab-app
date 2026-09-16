output "app_public_ip" {
  value = azurerm_public_ip.app.ip_address
}

output "postgres_fqdn" {
  value = azurerm_postgresql_flexible_server.db.fqdn
}

output "redis_hostname" {
  value = azurerm_redis_cache.cache.hostname
}
