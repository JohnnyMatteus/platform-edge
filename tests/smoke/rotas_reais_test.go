//go:build smoke

package smoke

import (
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
)

// Rotas reais do saas-multitenant (/api/v1) e da API de operação do
// payments-events-go (/api/v1, ADR 0011), conferidas no código dos projetos.
func TestRotasReaisDoSaaS(t *testing.T) {
	bruno := passwordToken(t, "studio-portal", "", "bruno.instrutor")
	diego := passwordToken(t, "studio-portal", "", "diego.visitante")

	tests := []struct {
		name   string
		token  string
		method string
		path   string
		body   string
		want   int
	}{
		{"studio reserva aula", bruno, http.MethodPost, "/api/v1/sessions/s-1/bookings", `{}`, http.StatusOK},
		{"studio cancela reserva", bruno, http.MethodPost, "/api/v1/bookings/b-1/cancel", ``, http.StatusOK},
		{"studio cria serie de aulas", bruno, http.MethodPost, "/api/v1/class-series", `{}`, http.StatusOK},
		{"studio edita aula", bruno, http.MethodPatch, "/api/v1/sessions/s-1", `{}`, http.StatusOK},
		{"studio consulta as proprias reservas", bruno, http.MethodGet, "/api/v1/me/bookings", "", http.StatusOK},
		{"studio consulta o perfil", bruno, http.MethodGet, "/api/v1/me", "", http.StatusOK},
		{"visitante nao reserva aula", diego, http.MethodPost, "/api/v1/sessions/s-1/bookings", `{}`, http.StatusForbidden},
		{"visitante nao le aulas", diego, http.MethodGet, "/api/v1/sessions", "", http.StatusForbidden},
		{"metodo fora da rota de escrita responde 404", bruno, http.MethodDelete, "/api/v1/sessions/s-1", "", http.StatusNotFound},
		{"rota sem caso no gateway responde 404", bruno, http.MethodPost, "/api/v1/me/whatsapp-link/code", "", http.StatusNotFound},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var body io.Reader
			if tt.body != "" {
				body = strings.NewReader(tt.body)
			}
			r := call(t, tt.method, tt.path, tt.token, body, nil)
			expectStatus(t, r, tt.want)
		})
	}
}

func TestAPIDeOperacaoDoPayments(t *testing.T) {
	// Token de operador de exemplo. O gateway não o valida (a rota não tem jwt)
	// e o stub também não; o app real checa o token contra OPERATOR_TOKENS.
	const operatorToken = "dev-only-operator-token-ana"

	t.Run("prefixo externo chega ao app como /api/v1", func(t *testing.T) {
		r := call(t, http.MethodGet, "/payments/api/v1/dead-letters", operatorToken, nil, nil)
		expectStatus(t, r, http.StatusOK)
		var echo struct {
			Path string `json:"path"`
		}
		if err := json.Unmarshal(r.body, &echo); err != nil {
			t.Fatalf("invalid echo: %v", err)
		}
		if echo.Path != "/api/v1/dead-letters" {
			t.Errorf("upstream path = %q, want /api/v1/dead-letters", echo.Path)
		}
	})

	t.Run("rate limit por IP de 60 por minuto", func(t *testing.T) {
		r := call(t, http.MethodGet, "/payments/api/v1/pipeline", operatorToken, nil, nil)
		expectStatus(t, r, http.StatusOK)
		if got := r.header.Get("RateLimit-Limit"); got != "60" {
			t.Errorf("RateLimit-Limit = %q, want 60", got)
		}
	})
}
