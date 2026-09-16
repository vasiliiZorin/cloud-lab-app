output "app_public_ip" {
  value = openstack_networking_floatingip_v2.app.address
}

output "db_private_ip" {
  value = openstack_compute_instance_v2.db.access_ip_v4
}

output "cache_private_ip" {
  value = openstack_compute_instance_v2.cache.access_ip_v4
}
