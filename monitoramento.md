# kube-prometheus-stack

## Instalação

Comando usado:

```bash
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 92.3.0
```

O release já estava instalado quando conferi o cluster, portanto não repeti `helm install` para evitar o erro de release existente. O `helm status` confirmou:

- **Release:** `kube-prometheus-stack`
- **Namespace:** `default`
- **Chart:** `kube-prometheus-stack-92.3.0`
- **Versão da aplicação:** `v0.94.1`
- **Status:** `deployed` — instalação concluída
- **Revisão:** `1`
- **Última implantação:** 12/10/2026 às 20:23:19

Na verificação, Grafana, Prometheus, Alertmanager, Operator, kube-state-metrics e os dois pods do node-exporter estavam prontos.

## Verificar o status

```bash
helm status kube-prometheus-stack --namespace default
kubectl --namespace default get pods -l "release=kube-prometheus-stack"
```

## Acessar o Grafana localmente

Obtenha a senha do usuário `admin`:

```bash
kubectl --namespace default get secrets kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d; echo
```

Inicie o encaminhamento local:

```bash
export POD_NAME=$(kubectl --namespace default get pod \
  -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=kube-prometheus-stack" \
  -o name)
kubectl --namespace default port-forward "$POD_NAME" 3000
```

Com o encaminhamento ativo, abra <http://localhost:3000> e entre com o usuário `admin` e a senha obtida acima.

Como alternativa, a senha pode ser consultada pelo Secret rotulado:

```bash
kubectl get secret --namespace default \
  -l app.kubernetes.io/component=admin-secret \
  -o jsonpath="{.items[0].data.admin-password}" | base64 --decode; echo
```

## Alertmanager e Prometheus Operator

Documentação para criar e configurar instâncias usando o Operator: <https://github.com/prometheus-operator/kube-prometheus>.
