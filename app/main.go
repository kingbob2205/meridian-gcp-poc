package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	secretmanager "cloud.google.com/go/secretmanager/apiv1"
	"cloud.google.com/go/secretmanager/apiv1/secretmanagerpb"
	"github.com/jackc/pgx/v5"
)

// gitCommit is injected at build time via -ldflags "-X main.gitCommit=<short-sha>".
var gitCommit = "unknown"

type healthResponse struct {
	Candidate string `json:"candidate"`
	Commit    string `json:"commit"`
	Region    string `json:"region"`
	DB        string `json:"db"`
	Secret    string `json:"secret"`
}

type secretReader func(ctx context.Context, resourceName string) (string, error)
type dbChecker func(ctx context.Context, password string) error

type serverConfig struct {
	candidateName   string
	commitSHA       string
	region          string
	apiTokenSecret  string
	dbPassSecret    string
	readSecret      secretReader
	checkDB         dbChecker
	requestTimeout  time.Duration
}

func envOrDefault(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

func newGCPSecretReader(client *secretmanager.Client) secretReader {
	return func(ctx context.Context, resourceName string) (string, error) {
		if resourceName == "" {
			return "", errors.New("secret resource name is empty")
		}
		resp, err := client.AccessSecretVersion(ctx, &secretmanagerpb.AccessSecretVersionRequest{
			Name: resourceName,
		})
		if err != nil {
			return "", err
		}
		val := strings.TrimSpace(string(resp.GetPayload().GetData()))
		if val == "" {
			return "", errors.New("secret payload is empty")
		}
		return val, nil
	}
}

func newPostgresChecker(host, port, user, dbName string) dbChecker {
	return func(ctx context.Context, password string) error {
		if host == "" || user == "" || dbName == "" {
			return errors.New("database connection parameters incomplete")
		}
		// Enforce TLS 1.2+ in transit against Cloud SQL (ssl_mode = ENCRYPTED_ONLY) via structured ConnConfig (no DSN interpolation).
		cfg, err := pgx.ParseConfig("")
		if err != nil {
			return err
		}
		cfg.Host = host
		cfg.Port = 5432
		if port != "" {
			if p, parseErr := net.LookupPort("tcp", port); parseErr == nil {
				cfg.Port = uint16(p)
			}
		}
		cfg.User = user
		cfg.Password = password
		cfg.Database = dbName
		cfg.ConnectTimeout = 4 * time.Second
		cfg.TLSConfig = &tls.Config{
			MinVersion:         tls.VersionTLS12,
			InsecureSkipVerify: true, // Cloud SQL server cert CN is project:instance, not the PSC internal IP.
		}
		cfg.Fallbacks = nil

		conn, err := pgx.ConnectConfig(ctx, cfg)
		if err != nil {
			return err
		}
		defer conn.Close(ctx)

		var result int
		if err := conn.QueryRow(ctx, "SELECT 1").Scan(&result); err != nil {
			return err
		}
		if result != 1 {
			return fmt.Errorf("unexpected SELECT 1 result: %d", result)
		}
		return nil
	}
}

func healthHandler(cfg serverConfig) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		timeout := cfg.requestTimeout
		if timeout == 0 {
			timeout = 8 * time.Second
		}
		ctx, cancel := context.WithTimeout(r.Context(), timeout)
		defer cancel()

		resp := healthResponse{
			Candidate: cfg.candidateName,
			Commit:    cfg.commitSHA,
			Region:    cfg.region,
			DB:        "error",
			Secret:    "error",
		}

		// 1. Live runtime read of third-party API token from GCP Secret Manager.
		if _, err := cfg.readSecret(ctx, cfg.apiTokenSecret); err != nil {
			log.Printf("healthcheck: failed reading third-party API token secret: %v", err)
		} else {
			resp.Secret = "ok"
		}

		// 2. Live runtime read of DB password from Secret Manager + real SQL query.
		dbPass, err := cfg.readSecret(ctx, cfg.dbPassSecret)
		if err != nil {
			log.Printf("healthcheck: failed reading database password secret: %v", err)
		} else if err := cfg.checkDB(ctx, dbPass); err != nil {
			log.Printf("healthcheck: database query failed: %v", err)
		} else {
			resp.DB = "ok"
		}

		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		if resp.DB == "ok" && resp.Secret == "ok" {
			w.WriteHeader(http.StatusOK)
		} else {
			w.WriteHeader(http.StatusServiceUnavailable)
		}
		_ = json.NewEncoder(w).Encode(resp)
	}
}

func main() {
	ctx := context.Background()
	smClient, err := secretmanager.NewClient(ctx)
	if err != nil {
		log.Fatalf("failed to initialize Secret Manager client: %v", err)
	}
	defer smClient.Close()

	commit := envOrDefault("GIT_COMMIT", gitCommit)
	cfg := serverConfig{
		candidateName:  envOrDefault("CANDIDATE_NAME", "Hazav Ogdan"),
		commitSHA:      commit,
		region:         envOrDefault("DEPLOY_REGION", "europe-west3"),
		apiTokenSecret: strings.TrimSpace(os.Getenv("SECRET_API_TOKEN_RESOURCE")),
		dbPassSecret:   strings.TrimSpace(os.Getenv("SECRET_DB_PASSWORD_RESOURCE")),
		readSecret:     newGCPSecretReader(smClient),
		checkDB: newPostgresChecker(
			strings.TrimSpace(os.Getenv("DB_HOST")),
			envOrDefault("DB_PORT", "5432"),
			envOrDefault("DB_USER", "meridian_app"),
			envOrDefault("DB_NAME", "meridian"),
		),
		requestTimeout: 8 * time.Second,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler(cfg))

	port := envOrDefault("PORT", "8080")
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("meridian-api listening on :%s (commit=%s, region=%s)", port, cfg.commitSHA, cfg.region)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("server error: %v", err)
	}
}
