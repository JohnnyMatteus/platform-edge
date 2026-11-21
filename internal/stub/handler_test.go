package stub

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

var fixedNow = func() time.Time { return time.Date(2026, 3, 10, 12, 0, 0, 0, time.UTC) }

func newTestHandler() *Handler {
	return NewHandler("payments-events-go", slog.New(slog.NewJSONHandler(io.Discard, nil)), fixedNow)
}

func TestHealthz(t *testing.T) {
	rec := httptest.NewRecorder()
	newTestHandler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), `"ok"`) {
		t.Fatalf("body = %q, want status ok", rec.Body.String())
	}
}

func TestEchoPropagatesGatewayHeaders(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/payments/v1/payments", strings.NewReader(`{"amount":1000}`))
	req.Header.Set(HeaderConsumer, "payments-ops")
	req.Header.Set(HeaderCredential, "payments-ops")
	req.Header.Set(HeaderRequestID, "req-123")
	req.Header.Set(HeaderTraceparent, "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
	rec := httptest.NewRecorder()

	newTestHandler().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	var got Echo
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("invalid json: %v", err)
	}
	want := Echo{
		Service:    "payments-events-go",
		Method:     http.MethodPost,
		Path:       "/payments/v1/payments",
		Consumer:   "payments-ops",
		Credential: "payments-ops",
		RequestID:  "req-123",
		TraceID:    "4bf92f3577b34da6a3ce929d0e0e4736",
		BodyBytes:  int64(len(`{"amount":1000}`)),
		ReceivedAt: "2026-03-10T12:00:00Z",
	}
	if got != want {
		t.Fatalf("echo = %+v\nwant  %+v", got, want)
	}
}

func TestEchoRejectsOversizedBody(t *testing.T) {
	body := strings.NewReader(strings.Repeat("x", maxBodyBytes+1))
	rec := httptest.NewRecorder()

	newTestHandler().ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/payments/v1/payments", body))

	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, want 413", rec.Code)
	}
}

func TestTraceID(t *testing.T) {
	tests := []struct {
		name        string
		traceparent string
		want        string
	}{
		{"valid", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01", "4bf92f3577b34da6a3ce929d0e0e4736"},
		{"empty", "", ""},
		{"too few parts", "00-4bf92f3577b34da6a3ce929d0e0e4736", ""},
		{"short trace id", "00-4bf92f35-00f067aa0ba902b7-01", ""},
		{"all zeros is invalid per W3C", "00-00000000000000000000000000000000-00f067aa0ba902b7-01", ""},
		{"uppercase is invalid per W3C", "00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01", ""},
		{"non hex", "00-zzf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01", ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := TraceID(tt.traceparent); got != tt.want {
				t.Fatalf("TraceID(%q) = %q, want %q", tt.traceparent, got, tt.want)
			}
		})
	}
}
