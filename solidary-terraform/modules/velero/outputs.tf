output "backup_bucket_name" {
  description = "Nome do bucket S3 onde os backups do Velero são armazenados"
  value       = aws_s3_bucket.velero_backups.bucket
}

output "backup_bucket_region" {
  description = "Região do bucket de backup (mesma região do cluster - AWS Academy restringe multi-região)"
  value       = var.region
}

output "backup_schedule_name" {
  description = "Nome do agendamento de backup (de hora em hora) criado"
  value       = "solidary-hourly-backup"
}

output "how_to_trigger_manual_backup" {
  description = "Comando para disparar um backup manual (útil para o vídeo de demonstração)"
  value       = "velero backup create demo-backup --include-namespaces solidary,observabilidade,argocd"
}

output "how_to_restore" {
  description = "Comando para restaurar a partir do backup mais recente (simular Disaster Recovery)"
  value       = "velero restore create --from-backup <NOME_DO_BACKUP>"
}
