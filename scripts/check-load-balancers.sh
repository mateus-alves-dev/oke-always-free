#!/usr/bin/env bash
# Confere se os Load Balancers do compartimento do cluster continuam dentro do
# Always Free: no máximo 1 LB, do tipo flexível, com banda mínima e máxima de
# 10 Mbps. Um segundo LB (por exemplo, um `Service type: LoadBalancer` criado
# além do Traefik) ou um LB com banda maior passa a ser cobrado.
set -euo pipefail

export SUPPRESS_LABEL_WARNING=True
cd "$(dirname "$0")/.."

compartment=$(oci ce cluster get \
  --cluster-id "$(terraform output -raw cluster_id)" \
  --query 'data."compartment-id"' --raw-output)

listar() {
  oci lb load-balancer list --compartment-id "$compartment" --all --query "$1" --output "$2"
}

listar 'data[*].{"name":"display-name","shape":"shape-name","min":"shape-details"."minimum-bandwidth-in-mbps","max":"shape-details"."maximum-bandwidth-in-mbps","state":"lifecycle-state"}' \
  table

count=$(listar 'length(data)' json)
excesso=$(listar 'length(data[? "shape-details"."maximum-bandwidth-in-mbps" > `10` || "shape-details"."minimum-bandwidth-in-mbps" > `10`])' json)
nao_flexivel=$(listar 'length(data[? "shape-name" != `flexible`])' json)

status=0

if [ "$count" -gt 1 ]; then
  echo
  echo "ATENCAO: $count Load Balancers no compartimento." \
    "O Always Free cobre apenas 1 flexivel de 10 Mbps; remova os demais."
  status=1
fi

if [ "$excesso" -gt 0 ]; then
  echo
  echo "ATENCAO: $excesso Load Balancer(s) com banda acima de 10 Mbps." \
    "Ajuste as anotacoes do Service (k8s/traefik-values.yaml) para 10/10."
  status=1
fi

if [ "$nao_flexivel" -gt 0 ]; then
  echo
  echo "ATENCAO: $nao_flexivel Load Balancer(s) fora do shape flexible." \
    "O Always Free exige shape flexible com min/max de 10 Mbps."
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo
  echo "OK: Load Balancers dentro do Always Free."
fi

exit "$status"
