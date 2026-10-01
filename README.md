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
| Load Balancer | 1 LB flexível de 10 Mbps, criado pelo Traefik | 1 LB flexível a 10 Mbps |

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

O endpoint do MySQL tem **somente IP privado**. A subnet privada não herda as regras de entrada da lista padrão da VCN. O NSG do banco aceita TCP/3306 apenas do NSG dos workers (pods do cluster) e do IP privado do Bastion. A porta MySQL X Protocol (33060) não está liberada. Uma política IAM específica permite que o próprio serviço MySQL associe seu VNIC a esse NSG.

A senha do administrador é gerada pelo Terraform, guardada no Vault e pode ser lida pela CLI — nunca a coloque no repositório:

```bash
oci secrets secret-bundle get \
  --secret-id "$(terraform output -raw mysql_admin_secret_id)" \
  --query 'data."secret-bundle-content".content' --raw-output | base64 -d
```

### Pelo cluster

O NSG dos workers já autoriza a porta 3306, então qualquer pod acessa o banco pelo IP privado (`terraform output -raw mysql_ip`). O exemplo abaixo cria o Secret, roda um Job com o cliente MySQL e mostra a versão do servidor:

```bash
kubectl create secret generic mysql-app-credentials \
  --from-literal=MYSQL_HOST="$(terraform output -raw mysql_ip)" \
  --from-literal=MYSQL_USER="$(terraform output -raw mysql_admin_username)" \
  --from-literal=MYSQL_PASSWORD="$(oci secrets secret-bundle get \
    --secret-id "$(terraform output -raw mysql_admin_secret_id)" \
    --query 'data."secret-bundle-content".content' --raw-output | base64 -d)"

kubectl apply -f k8s/apps/mysql-client.yaml
kubectl logs job/mysql-check      # imprime versão do servidor, usuário e host
kubectl delete job mysql-check
```

O Job usa a imagem oficial `mysql` (multi-arch, com build `linux/arm64`) e serve de modelo para as aplicações. Prefira criar um usuário MySQL por aplicação em vez de reutilizar o administrador. O Terraform não injeta o segredo em pods; a distribuição das credenciais é responsabilidade do seu fluxo de deploy.

### Pelo Bastion

Para administrar o banco de fora da VCN, crie uma sessão de **port forwarding** no Bastion (serviço gratuito, não consome cota Always Free) e conecte o cliente MySQL a `127.0.0.1`. O IP público do seu computador deve constar em `api_allowed_cidrs`.

```bash
# 1. cria a sessão e imprime o OCID dela (é o usuário da conexão SSH)
oci bastion session create-port-forwarding \
  --bastion-id "$(terraform output -raw bastion_id)" \
  --display-name admin-mysql --key-type PUB \
  --ssh-public-key-file ~/.ssh/id_ed25519.pub \
  --target-private-ip "$(terraform output -raw mysql_ip)" \
  --target-port 3306 --session-ttl 1800 \
  --query 'data.id' --raw-output

# 2. abre o túnel; a sessão leva alguns segundos para ficar ACTIVE (mantenha o terminal aberto)
ssh -i ~/.ssh/id_ed25519 -N -L 13306:$(terraform output -raw mysql_ip):3306 \
  <ocid-da-sessao>@host.bastion.<sua-regiao>.oci.oraclecloud.com

# 3. em outro terminal
mysql --host=127.0.0.1 --port=13306 --user="$(terraform output -raw mysql_admin_username)" -p
```

Sem `--wait-for-state` a CLI devolve a própria sessão; com ele, devolve o work request. A sessão expira sozinha no TTL (máximo de 3 horas) e pode ser encerrada antes com `oci bastion session delete --session-id <ocid> --force`.

## Object Storage e backups

O bucket `mysql_backup_bucket_name` é privado. A stack **não agenda exportações do MySQL**: use um job de aplicação no cluster e mantenha os objetos dentro da quota de 10 GB da tenancy. O grupo dinâmico `mysql_backup_workers` foi preservado da configuração existente; para dar acesso a jobs, crie uma política IAM específica para o bucket e ajuste a identidade usada pelo workload. Não conceda acesso amplo ao compartimento por padrão.

O MySQL Always Free mantém backup automático com retenção de um dia. Para retenção maior, exporte os dados para o bucket respeitando a quota.

O estado remoto em Object Storage é opcional. O exemplo de backend S3 em `versions.tf` permanece comentado; ativá-lo requer credenciais compatíveis, namespace e `terraform init -migrate-state`. Ele compartilha a quota do bucket de backups.

## Load Balancer e aplicações

O cluster tem **um único Load Balancer**, criado pelo OCI CCM para o `Service` do Traefik — o controlador de entrada que atende todas as aplicações por roteamento de host. As anotações que mantêm o LB no Always Free (flexível, 10 Mbps) ficam em `k8s/traefik-values.yaml`; sem elas o padrão do OKE é 100 Mbps e sai da franquia.

O Traefik foi escolhido porque o `ingress-nginx` foi aposentado em março de 2026 e não recebe mais correções de segurança.

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update traefik
helm upgrade --install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --version 41.6.1 -f k8s/traefik-values.yaml

kubectl get svc traefik -n traefik   # EXTERNAL-IP é o IP público do LB
```

Cada aplicação é publicada por um `Ingress`. Aponte o DNS de cada domínio para o IP do LB antes de testar:

```bash
kubectl apply -f k8s/apps/   # exemplos hello-oke e whoami
kubectl get ingress
```

O Traefik é a IngressClass padrão e está no namespace `traefik`; o dashboard não é exposto no LB (use `kubectl port-forward -n traefik svc/traefik 8080:8080` e acesse `http://localhost:8080/dashboard`).

Para publicar uma nova aplicação, crie Deployment + `Service` do tipo **ClusterIP** + `Ingress` com `host: seu.dominio`. Os arquivos em `k8s/apps/` servem de modelo.

O OCI CCM também cria regras de ingresso na security list da subnet privada (NodePorts do Traefik e porta 10256 do kube-proxy, com origem no CIDR do LoadBalancer). Por isso `oci_core_security_list.private` declara `ignore_changes = [ingress_security_rules]`: sem isso, cada `terraform apply` removeria essas regras e o CCM as recriaria logo depois.

Para conferir que o LB continua dentro da franquia (um único LB flexível de 10 Mbps):

```bash
./scripts/check-load-balancers.sh
```

Avisos de custo:

- **Nunca crie um segundo `Service` do tipo `LoadBalancer`.** Um segundo LB sai da franquia e ainda divide o roteamento por host entre dois IPs.
- HTTPS não está configurado: o Traefik responde na porta 443 com certificado próprio. Para certificados válidos (Let's Encrypt), instale o cert-manager; isso exige um domínio real apontando para o LB.
- A banda de 10 Mbps do LB é compartilhada por todas as aplicações.

Use imagens de contêiner `linux/arm64` nos workers A1. Instâncias A1 inativas podem ser recuperadas pela Oracle com base em métricas de CPU, rede e memória; a simples presença de um pod não impede isso. Consulte a [política de recuperação](https://docs.oracle.com/pt-br/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm).

## Destruição

```bash
terraform destroy
```

Confira backups e segredos antes de destruir a stack. O bucket pode conter dados enviados posteriormente; o Terraform não apaga objetos por conta própria.
