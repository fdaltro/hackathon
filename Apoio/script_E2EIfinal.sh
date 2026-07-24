#!/bin/bash

# =============================================================================
# SOLIDARY TECH - GERADOR DE CARGA SRE E2E (K8S)
#
# Baseado no script original do grupo. Única mudança: N workers rodando o
# fluxo em paralelo (WORKERS abaixo), em vez de 1 transação sequencial por
# vez - isso dá uma distribuição de latência real pro P95 do dashboard SRE,
# em vez da latência de uma única requisição isolada. Todos os fluxos são
# válidos, sem nenhum caminho de erro proposital.
#
# OBS: gerar mais tráfego não faz sozinho os spans de Postgres/SQS aparecerem
# no trace se o código do serviço não os instrumenta - isso é resolvido no
# código (main.go do donation-service), não aqui no script.
# =============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0;m'

NAMESPACE="solidary"   # Ajuste para o namespace da sua aplicação
WORKERS=4              # Quantas transações E2E rodam em paralelo

echo -e "${BLUE}======================================================="
echo -e "   SOLIDARY TECH - GERADOR DE CARGA SRE E2E (K8S)      "
echo -e "=======================================================${NC}\n"

echo -e "${YELLOW}>> Abrindo túneis de rede (Port-Forward) no namespace: $NAMESPACE...${NC}"
kubectl port-forward svc/ngo-service 8081:8081 -n "$NAMESPACE" > /dev/null 2>&1 &
kubectl port-forward svc/donation-service 8082:8082 -n "$NAMESPACE" > /dev/null 2>&1 &
kubectl port-forward svc/volunteer-service 8083:8083 -n "$NAMESPACE" > /dev/null 2>&1 &

# Mata port-forwards E todos os workers em background ao sair (Ctrl+C)
cleanup() {
  echo -e "\n${RED}🛑 Encerrando tráfego e fechando túneis...${NC}"
  pkill -f "kubectl port-forward" 2>/dev/null
  jobs -p | xargs -r kill 2>/dev/null
  wait 2>/dev/null
  exit 0
}
trap cleanup INT TERM

sleep 3
echo -e "${GREEN}✔ Conexões ativas! Iniciando $WORKERS workers em paralelo...${NC}"
echo -e "Pressione Ctrl+C para parar.\n"

CAUSAS=("Educacao" "Saude" "Meio Ambiente" "Apoio Social" "Direitos Humanos")
CIDADES=("Aracaju" "Sao Paulo" "Rio de Janeiro" "Curitiba" "Belo Horizonte")
DOADORES=("Fabricio Daltro" "Grupo 12" "Doador Anonimo" "Empresa Parceira")

# -----------------------------------------------------------------------------
# Um worker roda esse loop indefinidamente - $1 é o número do worker, só para
# identificar no log qual linha veio de qual transação concorrente.
# -----------------------------------------------------------------------------
worker_loop() {
  local WID=$1

  while true; do
    RAND_ID=$RANDOM$RANDOM
    CAUSA=${CAUSAS[$RAND_ID % ${#CAUSAS[@]}]}
    CIDADE=${CIDADES[$RAND_ID % ${#CIDADES[@]}]}
    DOADOR=${DOADORES[$RAND_ID % ${#DOADORES[@]}]}
    NGO_EMAIL="contato${RAND_ID}@ajudaglobal.org"

    echo -e "${BLUE}--- [W$WID | Transação | ID: $RAND_ID]${NC}"

    # -------------------------------------------------------------------
    # PASSO 1: Criar uma nova ONG
    # -------------------------------------------------------------------
    ONG_RESPONSE=$(curl -s -X POST http://localhost:8081/ngos \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"ONG Solidaria $RAND_ID\", \"email\": \"$NGO_EMAIL\", \"cause\": \"$CAUSA\", \"city\": \"$CIDADE\"}")

    ONG_ID=$(echo "$ONG_RESPONSE" | grep -o '"id": *[0-9]*' | head -1 | grep -o '[0-9]*')
    if [ -z "$ONG_ID" ]; then ONG_ID=1; fi
    echo -e "${GREEN}✔ [NGO]${NC} ONG criada (ID: $ONG_ID)"

    # -------------------------------------------------------------------
    # PASSO 2: Registrar uma Doação (Caminho Crítico / Hot Path)
    # -------------------------------------------------------------------
    VALOR=$((RANDOM % 500 + 10))
    curl -s -o /dev/null -X POST http://localhost:8082/donations \
      -H "Content-Type: application/json" \
      -d "{\"ngo_id\": $ONG_ID, \"amount\": $VALOR, \"donor_name\": \"$DOADOR\"}"
    echo -e "${GREEN}✔ [Donation]${NC} Doação de R\$$VALOR processada"

    # -------------------------------------------------------------------
    # PASSO 3: Cadastrar um Voluntário
    # -------------------------------------------------------------------
    curl -s -o /dev/null -X POST http://localhost:8083/volunteers \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"Voluntário $RAND_ID\", \"email\": \"voluntario${RAND_ID}@gmail.com\", \"ngo_id\": $ONG_ID}"
    echo -e "${GREEN}✔ [Volunteer]${NC} Voluntário registrado"

    # -------------------------------------------------------------------
    # PASSO 4: Validação (Tráfego de Leitura)
    # -------------------------------------------------------------------
    curl -s -o /dev/null http://localhost:8081/ngos
    curl -s -o /dev/null http://localhost:8082/donations
    curl -s -o /dev/null http://localhost:8083/volunteers/$ONG_ID
    echo -e "${YELLOW}✔ [Leitura]${NC} Consultas GET realizadas (W$WID)"

    echo ""
    # Jitter no sleep para não sincronizar todos os workers no mesmo instante
    sleep 0.$((RANDOM % 9 + 1))
  done
}

# Sobe os workers em paralelo, cada um em background
for i in $(seq 1 "$WORKERS"); do
  worker_loop "$i" &
done

echo -e "${CYAN}$WORKERS workers rodando (PIDs: $(jobs -p | tr '\n' ' '))${NC}\n"

wait
