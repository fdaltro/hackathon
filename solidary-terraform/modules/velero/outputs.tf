output "backup_bucket_name" {
  description = "Nome do bucket S3 onde os backups do Velero são armazenados"
  value       = aws_s3_bucket.velero_backups.bucket
}

output "backup_bucket_region" {
  description = "Região do bucket de backup - diferente da região do cluster (DR cross-region real)"
  value       = var.dr_region
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

output "dr_terraform_state_bucket" {
  description = "Bucket em Oregon (us-west-2) já preparado pra hospedar o Terraform state num failover real"
  value       = aws_s3_bucket.dr_terraform_state.bucket
}

output "how_to_failover" {
  description = "Procedimento para reconstruir a infraestrutura em Oregon durante um DR real"
  value       = <<-EOT
    1) terraform init -reconfigure \
         -backend-config="bucket=${aws_s3_bucket.dr_terraform_state.bucket}" \
         -backend-config="key=dr/terraform.tfstate" \
         -backend-config="region=us-west-2"
    2) terraform apply -var="region=us-west-2"
    3) aws eks update-kubeconfig --region us-west-2 --name solidary-eks
    4) velero backup get
    5) velero restore create --from-backup <NOME_DO_BACKUP_MAIS_RECENTE>
  EOT
}
