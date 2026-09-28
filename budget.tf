# O orçamento no compartimento raiz acompanha os custos da tenancy e dos filhos.
# Alertas são limites suaves: notificam, mas não impedem novas cobranças.
resource "oci_budget_budget" "tenancy_monthly" {
  compartment_id         = var.tenancy_ocid
  display_name           = "oke-free-tenancy-monthly"
  description            = "Monitoramento mensal dos custos de toda a tenancy."
  amount                 = 10
  reset_period           = "MONTHLY"
  processing_period_type = "MONTH"
  target_type            = "COMPARTMENT"
  targets                = [var.tenancy_ocid]
}

resource "oci_budget_alert_rule" "actual_spend" {
  for_each = toset(["1", "5", "10"])

  budget_id      = oci_budget_budget.tenancy_monthly.id
  display_name   = "gasto-real-${each.key}"
  description    = "Alerta quando o gasto mensal real atingir ${each.key} na moeda de cobrança da conta."
  threshold      = tonumber(each.key)
  threshold_type = "ABSOLUTE"
  type           = "ACTUAL"
  recipients     = var.billing_alert_email
  message        = "O gasto mensal real da tenancy atingiu o limite ${each.key}. Confira Billing & Cost Management na OCI."
}
