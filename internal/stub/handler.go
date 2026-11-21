// Package stub implementa um upstream HTTP mínimo que imita os serviços
// protegidos pelo gateway. Ele devolve, em JSON, o que o gateway propagou
// (consumidor, request id, contexto de trace) para que os smoke tests possam
// verificar o contrato entre gateway e upstream.
package stub

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"
)

const (
	HeaderConsumer    = "X-Consumer-Username"
	HeaderCredential  = "X-Credential-Identifier"
	HeaderSubject     = "X-Authenticated-Subject"
	HeaderRequestID   = "X-Kong-Request-Id"
	HeaderTraceparent = "Traceparent"
)

// healthPaths imita os health checks dos serviços reais: /healthz no
// payments-events-go e /up (padrão do Laravel) no saas-multitenant. O gateway
// usa esses caminhos nos health checks ativos dos upstreams.
var healthPaths = map[string]bool{"/healthz": true, "/up": true}

// maxBodyBytes protege o stub mesmo que o limite do gateway seja removido.
const maxBodyBytes = 1 << 20

type Echo struct {
	Service    string `json:"service"`
	Method     string `json:"method"`
	Path       string `json:"path"`
	Consumer   string `json:"consumer"`
	Credential string `json:"credential"`
	Subject    string `json:"subject"`
	RequestID  string `json:"request_id"`
	TraceID    string `json:"trace_id"`
	BodyBytes  int64  `json:"body_bytes"`
	ReceivedAt string `json:"received_at"`
}

type Handler struct {
	service string
	logger  *slog.Logger
	now     func() time.Time
}

func NewHandler(service string, logger *slog.Logger, now func() time.Time) *Handler {
	return &Handler{service: service, logger: logger, now: now}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if healthPaths[r.URL.Path] {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
		return
	}

	n, err := io.Copy(io.Discard, http.MaxBytesReader(w, r.Body, maxBodyBytes))
	if err != nil {
		h.logger.Warn("body rejected", "error", err.Error(), "path", r.URL.Path)
		writeJSON(w, http.StatusRequestEntityTooLarge, map[string]string{"message": "request body too large"})
		return
	}

	echo := Echo{
		Service:    h.service,
		Method:     r.Method,
		Path:       r.URL.Path,
		Consumer:   r.Header.Get(HeaderConsumer),
		Credential: r.Header.Get(HeaderCredential),
		Subject:    r.Header.Get(HeaderSubject),
		RequestID:  r.Header.Get(HeaderRequestID),
		TraceID:    TraceID(r.Header.Get(HeaderTraceparent)),
		BodyBytes:  n,
		ReceivedAt: h.now().UTC().Format(time.RFC3339),
	}

	h.logger.Info("request served",
		"method", echo.Method,
		"path", echo.Path,
		"consumer", echo.Consumer,
		"request_id", echo.RequestID,
		"trace_id", echo.TraceID,
	)
	writeJSON(w, http.StatusOK, echo)
}

// TraceID extrai o trace id de um cabeçalho W3C traceparent
// ("00-<trace-id>-<span-id>-<flags>"). Devolve "" se o formato for inválido.
func TraceID(traceparent string) string {
	parts := strings.Split(strings.TrimSpace(traceparent), "-")
	if len(parts) != 4 || len(parts[1]) != 32 {
		return ""
	}
	if strings.Trim(parts[1], "0") == "" || !isHex(parts[1]) {
		return ""
	}
	return parts[1]
}

func isHex(s string) bool {
	for _, c := range s {
		if !strings.ContainsRune("0123456789abcdef", c) {
			return false
		}
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
