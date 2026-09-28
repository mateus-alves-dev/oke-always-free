# OKE Always Free com Terraform

Esta stack provisiona um cluster **OKE Basic** e serviços auxiliares na região home da tenancy OCI. A configuração padrão foi dimensionada conforme a [documentação atual do Always Free](https://docs.oracle.com/pt-br/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm):

| Recurso | Configuração desta stack | Limite Always Free |
| --- | --- | --- |
| OKE | 1 cluster Basic | Control plane Basic gratuito |
| Compute A1 | 2 workers ARM de 1 OCPU e 6 GB cada | 2 OCPUs e 12 GB no total, equivalentes a 1.500 OCPU-h e 9.000 GB-h/mês |
| Block Volume | 2 boot volumes de 50 GB | 200 GB somados aos demais volumes da tenancy |
| MySQL HeatWave | 1 `MySQL.Free` de 50 GB e 1 nó `HeatWave.Free` | 1 sistema e 1 nó HeatWave Free na região home |
| Object Storage | 1 bucket privado Standard, sem versionamento; quota de 10 GB na tenancy | 20 GB combinados na conta somente Always Free; 10 GB Standard em conta paga/avaliação |
| Vault | 1 vault `DEFAULT`, 1 chave `SOFTWARE` e 1 segredo | Chaves de software gratuitas e 150 segredos |
| Bastion | 1 Bastion padrão, sessões temporárias | Serviço gratuito |

## Alertas de cobrança

O Terraform cria um orçamento mensal de 10 na **moeda de cobrança da conta OCI**, aplicado ao compartimento raiz e a todos os compartimentos filhos. Três regras enviam e-mail para `billing_alert_email` quando o gasto real acumulado no mês atingir 1, 5 e 10. Configure o endereço em `terraform.tfvars` antes de executar `terraform apply`.

Confirme que a moeda exibida em **Billing & Cost Management** é USD para interpretar esses valores como US$ 1, US$ 5 e US$ 10. A OCI avalia os alertas periodicamente, não em tempo real. O orçamento é um limite de aviso e **não bloqueia cobranças**.

As cotas de Compute, Block Volume, Object Storage e Vault são compartilhadas com outros recursos da tenancy. Confira **Governança e Administração → Limites, Cotas e Uso** antes de criar recursos fora desta stack. O plano do Terraform não controla recursos criados manualmente nem a quantidade de requisições ao Object Storage; a franquia gratuita é de 50.000 requisições por mês.

## Pré-requisitos

- Conta OCI com permissão para OKE, Compute, Networking, MySQL HeatWave, Vault, Bastion e Object Storage.
- Terraform >= 1.5, OCI CLI configurada e `kubectl`.
- Região definida em `terraform.tfvars` igual à região home da tenancy.
- Um CIDR público específico em `api_allowed_cidrs`; a mesma lista permite acesso ao endpoint da API Kubernetes e às sessões do Bastion.

## Provisionamento

```bash
cp terraform.tfvars.example terraform.tfvars
# Edite OCIDs, região home e api_allowed_cidrs no terraform.tfvars.
terraform init
terraform plan
terraform apply
export KUBECONFIG=$(terraform output -raw kubeconfig_path)
kubectl get nodes
```

`terraform.tfvars`, `terraform.tfstate` e `kubeconfig` são locais e ignorados pelo Git. A senha do administrador MySQL é gerada pelo Terraform, salva no Vault e **também permanece no estado do Terraform**; proteja esse arquivo ou use um backend remoto privado.

Para listar as versões Kubernetes disponíveis:

```bash
oci ce cluster-options get --cluster-option-id all \
  --query 'data."kubernetes-versions"' --raw-output
```

Antes de mudar `kubernetes_version`, confirme a imagem OKE ARM correspondente em `oci ce node-pool-options get --node-pool-option-id all`. As imagens dos workers são obtidas dessa lista de opções do OKE.

## Acesso ao MySQL

O endpoint do MySQL tem **somente IP privado**. A subnet privada não herda as regras de entrada da lista padrão da VCN. O NSG do banco aceita TCP/3306 apenas do NSG dos workers e do IP privado do Bastion. A porta MySQL X Protocol (33060) não está liberada. Uma política IAM específica permite que o próprio serviço MySQL associe seu VNIC a esse NSG.

Aplicações no cluster usam `terraform output -raw mysql_ip` na porta 3306. O Terraform cria o segredo no Vault, mas não o injeta em pods; configure a leitura do segredo e as permissões IAM da aplicação conforme seu método de implantação.

Para administrar o banco de fora da VCN, crie uma sessão de **port forwarding** no Bastion para o IP retornado por `mysql_ip` e a porta 3306. Pela OCI CLI:

```bash
oci bastion session create-port-forwarding \
  --bastion-id "$(terraform output -raw bastion_id)" \
  --target-private-ip "$(terraform output -raw mysql_ip)" \
  --target-port 3306 \
  --ssh-public-key-file ~/.ssh/id_ed25519.pub
```

Depois, copie o comando SSH da sessão na Console OCI e conecte o cliente MySQL a `127.0.0.1` na porta local escolhida. O IP público do seu computador deve constar em `api_allowed_cidrs`.

## Object Storage e backups

O bucket `mysql_backup_bucket_name` é privado. A stack **não agenda exportações do MySQL**: use um job de aplicação no cluster e mantenha os objetos dentro da quota de 10 GB da tenancy. O grupo dinâmico `mysql_backup_workers` foi preservado da configuração existente; para dar acesso a jobs, crie uma política IAM específica para o bucket e ajuste a identidade usada pelo workload. Não conceda acesso amplo ao compartimento por padrão.

O MySQL Always Free mantém backup automático com retenção de um dia. Para retenção maior, exporte os dados para o bucket respeitando a quota.

O estado remoto em Object Storage é opcional. O exemplo de backend S3 em `versions.tf` permanece comentado; ativá-lo requer credenciais compatíveis, namespace e `terraform init -migrate-state`. Ele compartilha a quota do bucket de backups.

## Load Balancer e custos

O cluster não cria um Load Balancer até que um `Service` Kubernetes do tipo `LoadBalancer` seja implantado. A Oracle oferece **um** LB Flexível Always Free a 10 Mbps. Configure as anotações abaixo no único serviço de entrada; o padrão do OKE pode ser de 100 Mbps e exceder o Always Free:

```yaml
metadata:
  annotations:
    oci.oraclecloud.com/load-balancer-type: "lb"
    service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
    service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"
    service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "10"
```

Use imagens de contêiner `linux/arm64` nos workers A1. Instâncias A1 inativas podem ser recuperadas pela Oracle com base em métricas de CPU, rede e memória; a simples presença de um pod não impede isso. Consulte a [política de recuperação](https://docs.oracle.com/pt-br/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm).

## Destruição

```bash
terraform destroy
```

Confira backups e segredos antes de destruir a stack. O bucket pode conter dados enviados posteriormente; o Terraform não apaga objetos por conta própria.
