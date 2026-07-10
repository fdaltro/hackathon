# --- Stage 1: Build e Isolamento de Dependências ---
FROM python:3.9-slim AS builder

WORKDIR /app

# Desabilita arquivos .pyc e otimiza o buffer de saída dos logs
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Cria o ambiente virtual para isolar as dependências (boto3, flask, gunicorn)
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copia e instala as dependências sem armazenar cache desnecessário
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --- Stage 2: Imagem Final de Produção (Leve e Segura) ---
FROM python:3.9-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
# Aponta para o virtualenv construído no estágio anterior
ENV PATH="/opt/venv/bin:$PATH"
ENV PORT=8083

# Copia apenas as dependências limpas do builder
COPY --from=builder /opt/venv /opt/venv

# Copia o código-fonte da aplicação
COPY app.py .

# Cria um usuário do sistema com ID não-privilegiado (non-root) por segurança
RUN useradd -u 10002 -m appuser && \
    chown -R appuser:appuser /app

# Expõe a porta nativa do serviço de voluntários
EXPOSE 8083

# Altera o contexto para o usuário não-raiz antes da execução
USER appuser

# Inicializa o serviço utilizando Gunicorn, envolvido pelo agente de
# auto-instrumentação do OpenTelemetry (zero-code instrumentation)
CMD ["opentelemetry-instrument", "gunicorn", "--bind", "0.0.0.0:8083", "--workers", "2", "--threads", "2", "app:app"]