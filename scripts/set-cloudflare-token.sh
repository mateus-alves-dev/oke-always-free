#!/usr/bin/env bash
# Lê o token no terminal sem eco e envia o Secret direto ao Kubernetes.
set +x
set -euo pipefail

command -v kubectl >/dev/null || { echo "kubectl não encontrado." >&2; exit 1; }
kubectl --request-timeout=15s get namespace cloudflare >/dev/null

trap 'unset tunnel_input tunnel_token' EXIT
IFS= read -r -s -p "Token ou comando 'cloudflared service install' (entrada oculta): " tunnel_input </dev/tty
printf '\n' >&2
if [[ "$tunnel_input" =~ ^(sudo[[:space:]]+)?cloudflared(\.exe)?[[:space:]]+service[[:space:]]+install[[:space:]]+([A-Za-z0-9_+/=-]+)$ ]]; then
  # O botão do painel copia o comando completo. Extraímos o token sem executá-lo.
  tunnel_token="${BASH_REMATCH[3]}"
elif [[ "$tunnel_input" =~ ^[A-Za-z0-9_+/=-]+$ ]]; then
  tunnel_token="$tunnel_input"
else
  echo "Informe o token ou o comando 'cloudflared service install TOKEN' copiado do painel." >&2
  exit 1
fi
unset tunnel_input

printf '%s' "$tunnel_token" |
  kubectl -n cloudflare create secret generic cloudflared-token \
    --from-file=token=/dev/stdin --dry-run=client -o yaml |
  kubectl --request-timeout=30s apply --server-side \
    --field-manager=cloudflare-token -f -
unset tunnel_token

echo "Secret atualizado. Após uma rotação, reinicie o Deployment conforme o README."
