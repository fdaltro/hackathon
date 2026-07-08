import os
import sys
import uuid
import time
import logging
import boto3
from flask import Flask, request, jsonify
from dotenv import load_dotenv

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

load_dotenv()

app = Flask(__name__)

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
DYNAMODB_TABLE = os.getenv("AWS_DYNAMODB_TABLE", "SolidaryTechVolunteers")

if not DYNAMODB_TABLE:
    log.critical("Erro: AWS_DYNAMODB_TABLE não definida.")
    sys.exit(1)

try:
    # Captura a URL do LocalStack se ela existir no ambiente (Docker local vs AWS Real)
    endpoint_url = os.getenv("AWS_ENDPOINT_URL")
    
    # Inicializa o recurso passando o endpoint (se for None, o boto3 usa a AWS real automaticamente)
    dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION, endpoint_url=endpoint_url)
    
    # Valida de forma resiliente se a tabela já existe no mock/nuvem
    try:
        table = dynamodb.Table(DYNAMODB_TABLE)
        table.load()  # Força uma chamada de metadados para testar se a tabela física existe
        log.info(f"Conectado à tabela DynamoDB existente: {DYNAMODB_TABLE}")
    except Exception:
        # Se a tabela não existir (comum em inicializações rápidas do LocalStack local), cria ela dinamicamente
        log.info(f"Tabela {DYNAMODB_TABLE} não encontrada localmente. Criando estrutura de mock...")
        table = dynamodb.create_table(
            TableName=DYNAMODB_TABLE,
            KeySchema=[{'AttributeName': 'volunteer_id', 'KeyType': 'HASH'}],
            AttributeDefinitions=[{'AttributeName': 'volunteer_id', 'AttributeType': 'S'}],
            BillingMode='PAY_PER_REQUEST'
        )
        # Aguarda a tabela estar 100% ativa no LocalStack para não dar erro nas rotas
        table.meta.client.get_waiter('table_exists').wait(TableName=DYNAMODB_TABLE)
        log.info(f"Tabela {DYNAMODB_TABLE} provisionada e pronta para uso.")

except Exception as e:
    log.critical(f"Falha crítica ao conectar ou estruturar o DynamoDB: {e}")
    sys.exit(1)

@app.route('/health')
def health():
    return jsonify({"status": "ok", "service": "volunteer-service"})

@app.route('/volunteers', methods=['POST'])
def register_volunteer():
    data = request.get_json()
    if not data or not all(k in data for k in ('name', 'email', 'ngo_id')):
        return jsonify({"error": "Campos obrigatórios ausentes"}), 400
    
    volunteer_id = str(uuid.uuid4())
    item = {
        'volunteer_id': volunteer_id,
        'name': data['name'],
        'email': data['email'],
        'ngo_id': int(data['ngo_id']),
        'registered_at': str(int(time.time()))
    }
    
    try:
        table.put_item(Item=item)
        return jsonify(item), 201
    except Exception as e:
        log.error(f"Erro ao salvar voluntário no DynamoDB: {e}")
        return jsonify({"error": "Erro interno ao processar dados"}), 500

@app.route('/volunteers/<int:ngo_id>', methods=['GET'])
def get_volunteers_by_ngo(ngo_id):
    try:
        # Nota para avaliação dos alunos: Operação Scan simplificada para fins de desenvolvimento.
        # Em cenários complexos de produção, índices globais secundários (GSI) seriam exigidos.
        response = table.scan(
            FilterExpression=boto3.dynamodb.conditions.Attr('ngo_id').eq(ngo_id)
        )
        return jsonify(response.get('Items', [])), 200
    except Exception as e:
        log.error(f"Erro ao buscar dados no DynamoDB: {e}")
        return jsonify({"error": "Erro interno"}), 500

if __name__ == '__main__':
    port = int(os.getenv("PORT", 8083))
    app.run(host='0.0.0.0', port=port)