# Alertas do AutoVitrine

Manifesto preparado para o kube-prometheus-stack existente, no namespace `autocommerce`.
Não instala chart, volume, nó ou LoadBalancer. A seleção existente inclui
`AlertmanagerConfig` de todos os namespaces e `PrometheusRule` com o label
`release: kube-prometheus-stack`.

Antes de aplicar `autovitrine-monitoring.json`, criar o Secret
`autovitrine-alert-email` com a chave `password` a partir do `SMTP_PASSWORD`
privado de deploy. Não colocar credenciais neste manifesto nem no Git.
O destinatário é o contato de suporte do AutoVitrine. Habilitar o envio apenas
com autorização do responsável e validar disparo e recuperação com uma sonda
sintética `AutoVitrineLaunchProbe`; remover a sonda após o teste.

Regras: ausência de réplica disponível por dois minutos; worker financeiro live
sem execução bem-sucedida há mais de cinco minutos, persistente por três minutos.
Aplicar a regra do worker depois de implantar o CronJob e conferir seu sucesso.

Diagnóstico: encaminhar localmente a porta do Alertmanager existente e conferir
os alertas `service=autovitrine`, o receptor selecionado e as métricas
`alertmanager_notifications_total`/`alertmanager_notifications_failed_total`
para a integração email. Aceitação SMTP não comprova leitura na caixa de entrada.
Para investigar a aplicação, usar os eventos estruturados `BILLING_*_RETRY`, sem
copiar tokens, mensagens privadas ou dados de clientes para evidências públicas.
