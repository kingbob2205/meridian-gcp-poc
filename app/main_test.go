package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthHandler_AllOK(t *testing.T) {
	cfg := serverConfig{
		candidateName:  "Hazav Ogdan",
		commitSHA:      "a1b2c3d",
		region:         "europe-west3",
		apiTokenSecret: "projects/test/secrets/api-token/versions/latest",
		dbPassSecret:   "projects/test/secrets/db-pass/versions/latest",
		readSecret: func(_ context.Context, name string) (string, error) {
			return "dummy-val-for-" + name, nil
		},
		checkDB: func(_ context.Context, _ string) error {
			return nil
		},
	}

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()
	healthHandler(cfg).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var got healthResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("invalid json: %v", err)
	}
	if got.Candidate != "Hazav Ogdan" || got.Commit != "a1b2c3d" || got.Region != "europe-west3" || got.DB != "ok" || got.Secret != "ok" {
		t.Fatalf("unexpected payload: %+v", got)
	}
}

func TestHealthHandler_SecretFailureReturns503(t *testing.T) {
	cfg := serverConfig{
		candidateName:  "Hazav Ogdan",
		commitSHA:      "a1b2c3d",
		region:         "europe-west3",
		apiTokenSecret: "projects/test/secrets/api-token/versions/latest",
		dbPassSecret:   "projects/test/secrets/db-pass/versions/latest",
		readSecret: func(_ context.Context, name string) (string, error) {
			if name == "projects/test/secrets/api-token/versions/latest" {
				return "", errors.New("permission denied")
			}
			return "db-secret", nil
		},
		checkDB: func(_ context.Context, _ string) error {
			return nil
		},
	}

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()
	healthHandler(cfg).ServeHTTP(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503, got %d", rec.Code)
	}

	var got healthResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("invalid json: %v", err)
	}
	if got.Secret != "error" || got.DB != "ok" {
		t.Fatalf("expected secret=error db=ok, got %+v", got)
	}
}

func TestHealthHandler_DBFailureReturns503(t *testing.T) {
	cfg := serverConfig{
		candidateName:  "Hazav Ogdan",
		commitSHA:      "a1b2c3d",
		region:         "europe-west3",
		apiTokenSecret: "projects/test/secrets/api-token/versions/latest",
		dbPassSecret:   "projects/test/secrets/db-pass/versions/latest",
		readSecret: func(_ context.Context, _ string) (string, error) {
			return "secret-ok", nil
		},
		checkDB: func(_ context.Context, _ string) error {
			return errors.New("connection refused")
		},
	}

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()
	healthHandler(cfg).ServeHTTP(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503, got %d", rec.Code)
	}

	var got healthResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("invalid json: %v", err)
	}
	if got.Secret != "ok" || got.DB != "error" {
		t.Fatalf("expected secret=ok db=error, got %+v", got)
	}
}
