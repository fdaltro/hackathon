package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
	_ "github.com/jackc/pgx/v4/stdlib"
	"github.com/joho/godotenv"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
)

type Donation struct {
	ID        int       `json:"id"`
	NgoID     int       `json:"ngo_id"`
	Amount    float64   `json:"amount"`
	DonorName string    `json:"donor_name"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

type App struct {
	DB          *sql.DB
	SqsSvc      *sqs.SQS
	SqsQueueURL string
}

// buildResource monta o Resource compartilhado (nome/versão do serviço)
// usado tanto pelo TracerProvider quanto pelo MeterProvider - garante
// que traces e métricas fiquem correlacionados sob o mesmo service_name.
func buildResource(ctx context.Context, serviceName string) *resource.Resource {
	res, _ := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName(serviceName),
			semconv.ServiceVersion("1.0.0"),
		),
	)
	return res
}

func resolveEndpointAndService() (endpoint string, serviceName string) {
	endpoint = os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		endpoint = "otel-collector.observabilidade.svc.cluster.local:4317"
	}
	endpoint = trimScheme(endpoint)

	serviceName = os.Getenv("OTEL_SERVICE_NAME")
	if serviceName == "" {
		serviceName = "donation-service"
	}
	return
}

// initTracer configura o SDK de TRACING do OpenTelemetry.
// Retorna uma função de shutdown que deve ser chamada ao encerrar a aplicação.
func initTracer() func(context.Context) error {
	ctx := context.Background()
	endpoint, serviceName := resolveEndpointAndService()

	exporter, err := otlptracegrpc.New(
		ctx,
		otlptracegrpc.WithEndpoint(endpoint),
		otlptracegrpc.WithInsecure(),
	)
	if err != nil {
		log.Printf("AVISO: não foi possível iniciar o exporter de traces OTLP (%v). Tracing desativado.", err)
		return func(context.Context) error { return nil }
	}

	res := buildResource(ctx, serviceName)

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)

	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	log.Printf("OpenTelemetry tracing ativado - exportando para %s", endpoint)
	return tp.Shutdown
}

// initMeter configura o SDK de MÉTRICAS do OpenTelemetry.
// Sem isso, o otelhttp.NewHandler usa um MeterProvider "no-op" e NENHUMA
// métrica HTTP (latência, contagem de requisições) é gerada - é exatamente
// isso que faltava para o dashboard de SLO/Error Budget funcionar de
// verdade com dados do donation-service.
func initMeter() func(context.Context) error {
	ctx := context.Background()
	endpoint, serviceName := resolveEndpointAndService()

	metricExporter, err := otlpmetricgrpc.New(
		ctx,
		otlpmetricgrpc.WithEndpoint(endpoint),
		otlpmetricgrpc.WithInsecure(),
	)
	if err != nil {
		log.Printf("AVISO: não foi possível iniciar o exporter de métricas OTLP (%v). Métricas desativadas.", err)
		return func(context.Context) error { return nil }
	}

	res := buildResource(ctx, serviceName)

	mp := metric.NewMeterProvider(
		metric.WithReader(metric.NewPeriodicReader(metricExporter)),
		metric.WithResource(res),
	)

	otel.SetMeterProvider(mp)

	log.Printf("OpenTelemetry metrics ativado - exportando para %s", endpoint)
	return mp.Shutdown
}

func trimScheme(endpoint string) string {
	endpoint = trimPrefix(endpoint, "http://")
	endpoint = trimPrefix(endpoint, "https://")
	return endpoint
}

func trimPrefix(s, prefix string) string {
	if len(s) >= len(prefix) && s[:len(prefix)] == prefix {
		return s[len(prefix):]
	}
	return s
}

func main() {
	_ = godotenv.Load()

	// --- Inicialização do OpenTelemetry (Traces + Métricas) ---
	shutdownTracer := initTracer()
	shutdownMeter := initMeter()
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := shutdownTracer(ctx); err != nil {
			log.Printf("Erro ao encerrar o exporter de tracing: %v", err)
		}
		if err := shutdownMeter(ctx); err != nil {
			log.Printf("Erro ao encerrar o exporter de métricas: %v", err)
		}
	}()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8082"
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL é obrigatória")
	}

	db, err := sql.Open("pgx", dbURL)
	if err != nil || db.Ping() != nil {
		log.Fatalf("Erro ao conectar ao banco de dados: %v", err)
	}
	log.Println("Conectado ao PostgreSQL (donation-service).")

	var sqsSvc *sqs.SQS
	queueURL := os.Getenv("AWS_SQS_URL")
	region := os.Getenv("AWS_REGION")
	if queueURL != "" && region != "" {
		sess, _ := session.NewSession(&aws.Config{Region: aws.String(region)})
		sqsSvc = sqs.New(sess)
		log.Println("Integração com AWS SQS ativada.")
	}

	app := &App{DB: db, SqsSvc: sqsSvc, SqsQueueURL: queueURL}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", app.HealthHandler)
	mux.HandleFunc("/donations", app.DonationHandler)

	// Envolve todas as rotas com o middleware de tracing + métricas do
	// OpenTelemetry - cada requisição HTTP vira um span E alimenta as
	// métricas http.server.* automaticamente (Golden Metrics para SRE).
	handler := otelhttp.NewHandler(mux, "donation-service")

	log.Printf("donation-service rodando na porta %s", port)
	log.Fatal(http.ListenAndServe(":"+port, handler))
}

func (a *App) HealthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"ok","service":"donation-service"}`))
}

func (a *App) DonationHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	if r.Method == http.MethodPost {
		var d Donation
		if err := json.NewDecoder(r.Body).Decode(&d); err != nil {
			http.Error(w, `{"error":"Payload inválido"}`, http.StatusBadRequest)
			return
		}

		d.Status = "APPROVED" // Simulação de gateway de pagamento
		err := a.DB.QueryRow(
			"INSERT INTO donations (ngo_id, amount, donor_name, status) VALUES ($1, $2, $3, $4) RETURNING id, created_at",
			d.NgoID, d.Amount, d.DonorName, d.Status,
		).Scan(&d.ID, &d.CreatedAt)

		if err != nil {
			log.Printf("Erro ao salvar doação: %v", err)
			http.Error(w, `{"error":"Erro interno"}`, http.StatusInternalServerError)
			return
		}

		if a.SqsSvc != nil {
			go a.sendNotificationEvent(d)
		}

		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(d)
		return
	}

	if r.Method == http.MethodGet {
		rows, err := a.DB.Query("SELECT id, ngo_id, amount, donor_name, status, created_at FROM donations ORDER BY id DESC")
		if err != nil {
			http.Error(w, `{"error":"Erro interno"}`, http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		donations := []Donation{}
		for rows.Next() {
			var d Donation
			rows.Scan(&d.ID, &d.NgoID, &d.Amount, &d.DonorName, &d.Status, &d.CreatedAt)
			donations = append(donations, d)
		}

		json.NewEncoder(w).Encode(donations)
		return
	}

	http.Error(w, `{"error":"Método não permitido"}`, http.StatusMethodNotAllowed)
}

func (a *App) sendNotificationEvent(d Donation) {
	body, _ := json.Marshal(d)
	_, err := a.SqsSvc.SendMessage(&sqs.SendMessageInput{
		MessageBody: aws.String(string(body)),
		QueueUrl:    aws.String(a.SqsQueueURL),
	})
	if err != nil {
		log.Printf("Falha ao despachar evento SQS: %v", err)
	}
}
