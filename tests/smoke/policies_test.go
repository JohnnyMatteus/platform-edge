//go:build smoke

package smoke

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"testing"
	"time"
)

const (
	paymentsOpsSecret  = "dev-only-payments-ops-secret"
	partnerBatchSecret = "dev-only-partner-batch-secret"
)

func TestAuthentication(t *testing.T) {
	now := time.Now().Unix()
	withClaim := func(key string, value any) map[string]any {
		c := validClaims("payments-ops", "payments.read")
		if value == nil {
			delete(c, key)
		} else {
			c[key] = value
		}
		return c
	}
	ana := passwordToken(t, "payments-ops", paymentsOpsSecret, "ana.operadora")

	tests := []struct {
		name  string
		token string
	}{
		{"missing token", ""},
		{"malformed token", "not-a-jwt"},
		{"tampered signature", ana[:len(ana)-4] + "AAAA"},
		{"expired token", mintToken(t, withClaim("exp", now-60))},
		{"lifetime above maximum_expiration", mintToken(t, withClaim("exp", now+3600))},
		{"untrusted issuer", mintToken(t, withClaim("iss", "http://evil.example.com/realms/edge"))},
		{"wrong audience", mintToken(t, withClaim("aud", "account"))},
		{"missing audience", mintToken(t, withClaim("aud", nil))},
		{"unknown client (azp)", mintToken(t, withClaim("azp", "unknown-client"))},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := call(t, http.MethodGet, "/payments/v1/payments", tt.token, nil, nil)
			expectStatus(t, r, http.StatusUnauthorized)
		})
	}

	t.Run("token signed by the realm key with valid claims", func(t *testing.T) {
		r := call(t, http.MethodGet, "/payments/v1/payments", mintToken(t, validClaims("payments-ops", "payments.read")), nil, nil)
		expectStatus(t, r, http.StatusOK)
	})
}

func TestAuthorizationByRoleAndRoute(t *testing.T) {
	ana := passwordToken(t, "payments-ops", paymentsOpsSecret, "ana.operadora")
	bruno := passwordToken(t, "studio-portal", "", "bruno.instrutor")
	carla := passwordToken(t, "studio-portal", "", "carla.gestora")
	diego := passwordToken(t, "studio-portal", "", "diego.visitante")

	tests := []struct {
		name   string
		token  string
		method string
		path   string
		want   int
	}{
		{"operator reads payments", ana, http.MethodGet, "/payments/v1/payments", http.StatusOK},
		{"instructor cannot read payments", bruno, http.MethodGet, "/payments/v1/payments", http.StatusForbidden},
		{"instructor reads classes", bruno, http.MethodGet, "/studios/v1/classes", http.StatusOK},
		{"manager reads classes (any-of roles)", carla, http.MethodGet, "/studios/v1/classes", http.StatusOK},
		{"instructor cannot reach admin", bruno, http.MethodGet, "/studios/v1/admin/plans", http.StatusForbidden},
		{"manager reaches admin", carla, http.MethodGet, "/studios/v1/admin/plans", http.StatusOK},
		{"user without roles is forbidden", diego, http.MethodGet, "/studios/v1/classes", http.StatusForbidden},
		{"route without explicit policy is denied by default", ana, http.MethodPost, "/payments/v1/refunds", http.StatusForbidden},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			expectStatus(t, call(t, tt.method, tt.path, tt.token, nil, nil), tt.want)
		})
	}
}

func TestUpstreamReceivesTrustedIdentity(t *testing.T) {
	bruno := passwordToken(t, "studio-portal", "", "bruno.instrutor")

	r := call(t, http.MethodGet, "/studios/v1/classes", bruno, nil, map[string]string{
		"X-Authenticated-Subject": "spoofed-admin",
	})
	expectStatus(t, r, http.StatusOK)

	var echo struct {
		Service   string `json:"service"`
		Consumer  string `json:"consumer"`
		Subject   string `json:"subject"`
		RequestID string `json:"request_id"`
		TraceID   string `json:"trace_id"`
	}
	if err := json.Unmarshal(r.body, &echo); err != nil {
		t.Fatalf("invalid echo: %v", err)
	}
	if echo.Service != "saas-multitenant" {
		t.Errorf("service = %q, want saas-multitenant", echo.Service)
	}
	if echo.Consumer != "studio-portal" {
		t.Errorf("consumer = %q, want studio-portal (from azp)", echo.Consumer)
	}
	if echo.Subject == "" || echo.Subject == "spoofed-admin" {
		t.Errorf("subject = %q, want the token sub, never the client header", echo.Subject)
	}
	if echo.RequestID == "" || echo.RequestID != r.header.Get("X-Kong-Request-Id") {
		t.Errorf("request id not propagated: upstream %q, response %q", echo.RequestID, r.header.Get("X-Kong-Request-Id"))
	}
	if len(echo.TraceID) != 32 {
		t.Errorf("trace id = %q, want a W3C trace id injected by the gateway", echo.TraceID)
	}
}

func TestRateLimitPerClientAndRoute(t *testing.T) {
	ana := passwordToken(t, "payments-ops", paymentsOpsSecret, "ana.operadora")
	partner := clientCredentialsToken(t, "partner-batch", partnerBatchSecret)

	// payments-write permite 5/min para payments-ops. A janela é fixa por
	// minuto, então o laço tolera execuções repetidas no mesmo minuto.
	var limited response
	for i := 0; i < 7; i++ {
		r := call(t, http.MethodPost, "/payments/v1/payments", ana, strings.NewReader(`{"amount":1}`), nil)
		if r.status == http.StatusTooManyRequests {
			limited = r
			break
		}
		expectStatus(t, r, http.StatusOK)
		if got := r.header.Get("RateLimit-Limit"); got != "5" {
			t.Fatalf("RateLimit-Limit = %q, want 5", got)
		}
	}
	if limited.status != http.StatusTooManyRequests {
		t.Fatal("expected 429 after exceeding 5 requests per minute")
	}

	t.Run("429 carries rate limit headers", func(t *testing.T) {
		h := limited.header
		if h.Get("RateLimit-Limit") != "5" || h.Get("RateLimit-Remaining") != "0" {
			t.Errorf("RateLimit-Limit=%q RateLimit-Remaining=%q, want 5 and 0",
				h.Get("RateLimit-Limit"), h.Get("RateLimit-Remaining"))
		}
		retry, err := strconv.Atoi(h.Get("Retry-After"))
		if err != nil || retry < 1 || retry > 60 {
			t.Errorf("Retry-After = %q, want seconds in [1,60]", h.Get("Retry-After"))
		}
		if !strings.Contains(string(limited.body), "Rate limit exceeded") {
			t.Errorf("body = %s", limited.body)
		}
	})

	t.Run("another client keeps its own quota on the same route", func(t *testing.T) {
		r := call(t, http.MethodPost, "/payments/v1/payments", partner, strings.NewReader(`{"amount":1}`), nil)
		expectStatus(t, r, http.StatusOK)
		if got := r.header.Get("RateLimit-Limit"); got != "20" {
			t.Errorf("RateLimit-Limit = %q, want 20 (partner contract)", got)
		}
	})

	t.Run("the same client keeps its quota on another route", func(t *testing.T) {
		r := call(t, http.MethodGet, "/payments/v1/payments", ana, nil, nil)
		expectStatus(t, r, http.StatusOK)
		if got := r.header.Get("RateLimit-Limit"); got != "60" {
			t.Errorf("RateLimit-Limit = %q, want 60 (payments-read)", got)
		}
	})
}

func TestPublicRouteIsLimitedByIP(t *testing.T) {
	r := call(t, http.MethodGet, "/studios/v1/public/schedule", "", nil, nil)
	if r.status != http.StatusOK && r.status != http.StatusTooManyRequests {
		t.Fatalf("status = %d, want 200 (or 429 on repeated runs)", r.status)
	}
	if r.header.Get("RateLimit-Limit") != "30" {
		t.Errorf("RateLimit-Limit = %q, want 30", r.header.Get("RateLimit-Limit"))
	}
}

func TestPayloadLimit(t *testing.T) {
	ana := passwordToken(t, "payments-ops", paymentsOpsSecret, "ana.operadora")
	body := strings.NewReader(`{"memo":"` + strings.Repeat("x", 17*1024) + `"}`)

	r := call(t, http.MethodPost, "/payments/v1/payments", ana, body, map[string]string{"Content-Type": "application/json"})
	expectStatus(t, r, http.StatusRequestEntityTooLarge)
}

func TestCORS(t *testing.T) {
	preflight := func(origin string) response {
		return call(t, http.MethodOptions, "/studios/v1/classes", "", nil, map[string]string{
			"Origin":                         origin,
			"Access-Control-Request-Method":  http.MethodGet,
			"Access-Control-Request-Headers": "Authorization",
		})
	}

	t.Run("allowed origin gets preflight headers without a token", func(t *testing.T) {
		r := preflight("http://localhost:5173")
		expectStatus(t, r, http.StatusOK)
		if got := r.header.Get("Access-Control-Allow-Origin"); got != "http://localhost:5173" {
			t.Errorf("Access-Control-Allow-Origin = %q", got)
		}
	})

	t.Run("unknown origin is not echoed back", func(t *testing.T) {
		r := preflight("http://evil.example.com")
		if got := r.header.Get("Access-Control-Allow-Origin"); got == "http://evil.example.com" || got == "*" {
			t.Errorf("Access-Control-Allow-Origin = %q, must not allow unknown origin", got)
		}
	})
}

func TestSecurityHeaders(t *testing.T) {
	r := call(t, http.MethodGet, "/studios/v1/public/schedule", "", nil, nil)
	for header, want := range map[string]string{
		"X-Content-Type-Options": "nosniff",
		"X-Frame-Options":        "DENY",
		"Cache-Control":          "no-store",
	} {
		if got := r.header.Get(header); got != want {
			t.Errorf("%s = %q, want %q", header, got, want)
		}
	}
	for _, leaked := range []string{"Server", "Via", "X-Kong-Upstream-Latency", "X-Kong-Proxy-Latency"} {
		if v := r.header.Get(leaked); v != "" {
			t.Errorf("header %s leaks implementation details: %q", leaked, v)
		}
	}
}
