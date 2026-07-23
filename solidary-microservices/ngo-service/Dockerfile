# --- Stage 1: Build e Instalação de Dependências --
FROM python:3.9-slim AS builder

WORKDIR /app

# Desabilita a escrita de arquivos .pyc no disco e ativa o buffer de logs do python
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Atualiza os pacotes e instala ferramentas mínimas de build se necessário
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Cria um diretório virtual para isolar as dependências instaladas
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copia e instala as dependências utilizando cache de camadas do Docker
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --- Stage 2: Imagem Final de Execução (Leve e Segura) ---
FROM python:3.9-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
# Garante que o Python usará as dependências compiladas no estágio anterior
ENV PATH="/opt/venv/bin:$PATH"
ENV PORT=8081

# Copia o ambiente virtual com as dependências do builder
COPY --from=builder /opt/venv /opt/venv

# Copia o código fonte da aplicação
COPY app.py .

# Cria um usuário de sistema não-raiz (non-root) para rodar o container de forma segura
RUN useradd -u 10001 -m appuser && \
    chown -R appuser:appuser /app

# Expõe a porta nativa do serviço
EXPOSE 8081

# Altera o contexto de execução para o usuário não-privilegiado
USER appuser

# Executa a aplicação usando o Gunicorn em produção, envolvido pelo
# agente de auto-instrumentação do OpenTelemetry (zero-code instrumentation)
CMD ["opentelemetry-instrument", "gunicorn", "--bind", "0.0.0.0:8081", "--workers", "2", "--threads", "2", "app:app"]