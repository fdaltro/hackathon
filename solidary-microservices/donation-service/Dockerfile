# --- Stage 1: Build da aplicação ---
FROM golang:1.21-alpine AS builder

# Instala certificados SSL e ferramentas básicas de compilação
RUN apk update && apk add --no-cache git ca-certificates && update-ca-certificates

# Define o diretório de trabalho
WORKDIR /app

# Copia os arquivos de definição de dependências primeiro (otimiza o cache de camadas)
COPY go.mod go.sum* ./
RUN go mod download

# Copia o restante do código fonte
COPY . .

# Compila o binário de forma estática (sem dependências de CGO) e otimizado para produção
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s" \
    -o donation-service .

# --- Stage 2: Imagem final de execução (Segura e Otimizada) ---
# Usamos a imagem distroless estática por ser minimalista e segura
FROM gcr.io/distroless/static-debian12:latest

WORKDIR /

# Copia os certificados SSL gerados no builder (essencial para chamadas à AWS)
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copia o binário compilado do estágio anterior
COPY --from=builder /app/donation-service /donation-service

# Define as variáveis de ambiente padrão caso não sejam injetadas pelo Kubernetes
ENV PORT=8082

# Expõe a porta do serviço
EXPOSE 8082

# Garante que o container rode com o usuário padrão não-privilegiado (non-root) do distroless
USER 65532:65532

# Comando de inicialização
ENTRYPOINT ["/donation-service"]