# Acesso privado ao OKE e MySQL com WARP

O caminho é **computador com WARP → Cloudflare → cloudflared nos workers → API privada ou MySQL**. O IP público do computador pode mudar sem alterar a configuração OCI. Não é necessário um domínio próprio, DNS público ou outro LoadBalancer. O tráfego das aplicações pelo Traefik continua como está.

O túnel é gerenciado pelo painel Cloudflare, não pelo Terraform. Os manifests criam duas réplicas nos workers ARM existentes. O token só fica no Secret `cloudflared-token`, no namespace `cloudflare`; não o coloque em YAML versionado, variáveis Terraform ou mensagens. Quem puder ler esse Secret terá acesso à credencial do conector.

## 1. Preparar a stack e obter os destinos

Na primeira configuração, use o kubeconfig público com seu IP atual em `api_allowed_cidrs`. Aplique as adições Terraform somente após revisar o plano:

```bash
terraform init
terraform plan
terraform apply
export KUBECONFIG="$(terraform output -raw kubeconfig_path)"
kubectl get nodes

# A API retorna IP:porta; no painel use somente o IP, com /32.
terraform output -raw cluster_private_endpoint
terraform output -raw mysql_ip
terraform console <<< 'var.vcn_cidr'
```

Anote `API_IP`, `MYSQL_IP` e `VCN_CIDR`. Não cadastre a VCN inteira como rota. O kubeconfig privado já inclui a CA do OKE e a autenticação via OCI CLI; não edite o certificado nem use `insecure-skip-tls-verify`.

## 2. Organização e identidade

1. Entre no [painel Cloudflare](https://dash.cloudflare.com/) e abra **Zero Trust**. Se ainda não houver organização, escolha um nome de equipe disponível e o plano **Free**. Se já existir uma organização, aproveite o nome atual.
2. Em **Integrações → Provedores de identidade**, habilite **One-time PIN** para login com código recebido por e-mail.
3. Em **Equipe e recursos → Dispositivos → Gerenciamento/Registro de dispositivos**, configure a permissão de registro: ação **Allow**, seletor **Emails**, valor exato do seu e-mail. Use esse método de login na política. Não use `Everyone` nem autorize todo o domínio do e-mail.

Esse login controla o ingresso no Zero Trust. As políticas de rede abaixo restringem os destinos; a autenticação OCI e as credenciais MySQL continuam necessárias.

## 3. Políticas e perfil do WARP

Prepare as políticas **antes de conectar o computador**, pois dispositivos registrados podem acessar as rotas privadas quando não há política de bloqueio.

Em **Traffic controls → Policies → Network** (ou **Gateway → Firewall policies → Network**), crie estas regras na ordem indicada. Combine as condições de cada linha com **AND**:

| Ordem | Nome | Ação | Condições |
| --- | --- | --- | --- |
| 1 | `oke-api-admin` | Allow | User Email = seu e-mail; Destination IP em `API_IP/32`; Destination Port = `6443`; Protocol = TCP |
| 2 | `oke-mysql-admin` | Allow | User Email = seu e-mail; Destination IP em `MYSQL_IP/32`; Destination Port = `3306`; Protocol = TCP |
| 3 | `oke-block-vcn` | Block | Destination IP em `VCN_CIDR` |

Não deve existir uma regra Allow genérica antes dessas regras. Com essas políticas, outra identidade não pode usar nem mesmo as duas portas permitidas.

Em **Traffic controls → Traffic settings → Proxy and inspection**, habilite o proxy Gateway para **TCP**. Esses acessos por IP não precisam de DNS privado, proxy UDP ou ICMP. Mantenha TLS de ponta a ponta: não habilite inspeção/decriptação TLS para esses destinos; se já houver inspeção global, exclua os IPs privados da API e MySQL dessa inspeção.

Em **Equipe e recursos → Dispositivos → Perfis de dispositivo**, configure o perfil aplicado ao seu usuário:

- Modo de serviço **Traffic and DNS** (WARP), não somente DNS nem somente postura.
- **Split Tunnels → Include IPs and domains**: adicionar `API_IP/32` e `MYSQL_IP/32`.
- Adicionar também `<nome-da-equipe>.cloudflareaccess.com`, necessário ao login e às sessões do cliente nesse modo. Se futuramente usar outro provedor de identidade, incluir seus domínios de autenticação conforme a documentação Cloudflare.

Só esses destinos de aplicação e o domínio de autenticação entram no túnel. O modo Include controla tráfego IP; no modo Traffic and DNS, as consultas DNS ainda passam pelo Gateway. Não inclua `0.0.0.0/0`, as redes de pods/Services nem a VCN inteira. Se sua rede local ou outra VPN usar os mesmos IPs privados, resolva o conflito antes de conectar.

## 4. Criar o túnel e as rotas

1. No painel, abra **Rede/Networking → Tunnels → Create tunnel** e escolha **Cloudflared**.
2. Nomeie o túnel `oke-private` e copie **apenas o token** do comando de instalação. Não execute a instalação do conector no Mac: ele rodará nos workers.
3. Em **CIDR routes/Private networks**, adicione `API_IP/32` e `MYSQL_IP/32` ao mesmo túnel, na rede virtual padrão. Não crie rotas de aplicação publicada ou hostnames públicos.

As rotas são IPs, sem esquema `https://` e sem porta. As portas são limitadas pelas políticas Gateway. A saída existente dos workers via NAT já permite as conexões do conector à Cloudflare (TCP/UDP 7844); nenhuma porta de entrada nova é necessária.

## 5. Implantar o conector

Na raiz do repositório, usando ainda o kubeconfig público:

```bash
kubectl apply -f k8s/cloudflare/namespace.yaml
./scripts/set-cloudflare-token.sh
kubectl apply -f k8s/cloudflare/deployment.yaml
kubectl -n cloudflare rollout status deployment/cloudflared --timeout=180s
kubectl -n cloudflare get pods -o wide
```

O script solicita o token com entrada oculta e envia o Secret diretamente ao Kubernetes; não escreve arquivo temporário nem coloca o valor nos argumentos ou histórico do shell. Também aceita o comando `cloudflared service install TOKEN` (ou `cloudflared.exe service install TOKEN`) copiado pelo botão do painel: extrai somente o token, sem executar o comando. Usa o contexto de `KUBECONFIG` atual. Aplique o namespace antes do Secret e o Secret antes do Deployment.

Confirme dois pods `Ready`, preferencialmente em workers distintos, e o túnel **Healthy** no painel. A distribuição entre workers é preferencial para continuar funcionando quando só um worker estiver disponível. Não há HPA: as duas réplicas usam o mesmo token e servem para disponibilidade, não balanceamento de carga. Cada pod reserva 100m CPU e 128 MiB; os limites são 500m CPU e 256 MiB. A imagem está fixada por versão e digest multi-arch, com `linux/arm64` verificado.

O conector roda sem root, sem token de ServiceAccount, sem privilégios, com sistema de arquivos somente leitura e sem Service ou Ingress. O token é montado como arquivo somente leitura. O probe `/ready` confirma conexão à Cloudflare; o probe `/metrics` verifica o processo sem reiniciá-lo só porque a Cloudflare ficou indisponível. Um túnel Healthy não prova acesso aos destinos: execute os testes abaixo.

## 6. Conectar o Mac e usar

Instale ou abra o [Cloudflare One Client (WARP) para macOS](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/cloudflare-one-client/downloads/). No cliente, abra **Preferências/Configurações → Conta → Login with Cloudflare Zero Trust**, informe o nome da equipe, autentique com o e-mail autorizado e ative a conexão. Se aparecer uma solicitação do macOS para habilitar a extensão de rede/VPN, conclua essa etapa no sistema.

No cliente novo, escolha **Cloudflare One Client → Continue** e informe o nome da equipe em **What is your team name?**. Se o navegador insistir em uma organização antiga, confira `warp-cli registration organization` e saia da organização anterior pela interface antes de iniciar o novo registro. `warp-cli registration new <nome-da-equipe>` abre o login correto no navegador, mas a mensagem de sucesso da CLI só confirma o início do fluxo: ainda é necessário validar o código recebido por e-mail e permitir o retorno ao aplicativo. Confirme a organização e o status conectado antes de testar o cluster.

```bash
warp-cli status
export KUBECONFIG="$(terraform output -raw kubeconfig_private_path)"
kubectl --request-timeout=15s get nodes

# -p pede a senha sem colocá-la no histórico; TLS é obrigatório.
mysql --protocol=TCP --host="$(terraform output -raw mysql_ip)" --port=3306 \
  --user="$(terraform output -raw mysql_admin_username)" \
  --ssl-mode=REQUIRED -p \
  -e "SELECT 1; SHOW SESSION STATUS LIKE 'Ssl_cipher';"
```

O cliente precisa ser o cliente Oracle MySQL, que suporta `--ssl-mode`. Para uma GUI, use o IP privado do banco, porta 3306, conexão direta e SSL obrigatório, sem túnel SSH. Use as credenciais existentes; a leitura da senha no Vault está documentada no README principal. Não é necessário criar sessão Bastion.

## 7. Verificar o acesso

- Com WARP conectado e o kubeconfig privado: testar `get nodes`, logs, `exec` e port-forward em um pod de aplicação existente. Conexões já abertas podem cair durante uma falha de réplica; novas conexões devem funcionar pela outra.
- Executar a consulta MySQL acima e confirmar `Ssl_cipher` preenchido.
- Desconectar WARP e repetir o acesso **aos IPs privados**, com timeout: deve falhar. O acesso público por um IP ainda autorizado é independente.
- Reconectar e verificar no Gateway, com o teste de políticas/logs, que outro e-mail e portas como 33060 são bloqueados. Uma falha em uma porta fechada por si só não comprova que a política funcionou; conferir a regra aplicada. Não autorizar outro usuário só para esse teste.
- Validar políticas com uma requisição de aplicação completa: abrir somente um socket TCP não comprova que o tráfego de aplicação foi permitido pelo Gateway.
- Com as duas réplicas prontas, excluir **um** pod `cloudflared` e repetir novas conexões enquanto o Deployment o recria. Não excluir o Deployment para testar disponibilidade.
- Executar `./scripts/check-load-balancers.sh`: deve continuar existindo somente o LB flexível de 10 Mbps do Traefik.

## Rotação, atualização e recuperação

Para trocar o token, siga a [rotação oficial](https://developers.cloudflare.com/tunnel/reference/tunnel-tokens/) no painel. Atualize o Secret e reinicie as réplicas; a atualização do arquivo montado não reinicia o processo:

```bash
./scripts/set-cloudflare-token.sh
kubectl -n cloudflare rollout restart deployment/cloudflared
kubectl -n cloudflare rollout status deployment/cloudflared --timeout=180s
```

Ao atualizar `cloudflared`, confirme a plataforma `linux/arm64` no índice, atualize versão e digest no manifest e faça o rollout. Não use `latest`.

Se os workers ou o túnel pararem, a administração pelo WARP também para. Mantenha a API pública habilitada com a lista restrita `api_allowed_cidrs`. Para recuperar acesso:

1. Obtenha seu IP atual com `curl -4 https://api.ipify.org` e atualize **somente** seu `/32` em `terraform.tfvars`.
2. Revise `terraform plan` e aplique a alteração da lista; não abra `0.0.0.0/0` nem aceite substituições de recursos para recuperar acesso.
3. Execute `export KUBECONFIG="$(terraform output -raw kubeconfig_path)"` e corrija o conector com `kubectl`. O mesmo `/32` permite sessões Bastion para o MySQL.
4. Após restaurar o túnel, volte para `kubeconfig_private_path`. Não é necessário atualizar o IP nas mudanças seguintes da sua conexão para usar WARP.

Se o conector não ficar Ready, consulte `kubectl -n cloudflare logs deployment/cloudflared --tail=50`, token, saída 7844 e status Cloudflare. Se ele estiver Ready mas o destino der timeout, confira rotas `/32`, perfil WARP, políticas Gateway e NSGs. O NSG continua vendo conexões originadas nos workers, não o IP do computador. Se falhar só a autenticação, confira OCI CLI/RBAC ou credenciais MySQL.

Se o cluster ou banco forem recriados e seus IPs mudarem, atualize as duas rotas no túnel, as políticas de destino e o perfil Split Tunnels. Regere os kubeconfigs com Terraform. Revogue o túnel no painel e remova as rotas/políticas/perfil antes de abandonar esta integração; o Terraform não gerencia os recursos Cloudflare.

## Referências

- [Acesso privado por IP com cloudflared e WARP](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/private-net/cloudflared/connect-cidr/)
- [Cloudflared em Kubernetes](https://developers.cloudflare.com/tunnel/guides/kubernetes/)
- [Split Tunnels e domínios de autenticação no modo Include](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/cloudflare-one-client/configure/route-traffic/split-tunnels/)
- [Parâmetros do conector, incluindo token-file](https://developers.cloudflare.com/tunnel/reference/run-parameters/)
