//go:build smoke

package smoke

import (
	"net/http"
	"strconv"
	"testing"
	"time"
)

// Prova a contagem compartilhada (ADR 0010): chamadas alternadas entre duas
// instâncias do gateway consomem a mesma cota. Com policy local, cada
// instância contaria sozinha e o restante nunca cairia de um em um.
func TestRateLimitIsSharedAcrossGatewayInstances(t *testing.T) {
	if err := waitFor(gatewayReplicaURL+"/studios/v1/public/schedule", 60*time.Second); err != nil {
		t.Fatalf("second gateway instance not available at %s: %v", gatewayReplicaURL, err)
	}
	ana := passwordToken(t, "payments-ops", paymentsOpsSecret, "ana.operadora")
	bases := []string{gatewayURL, gatewayReplicaURL}

	// A janela é fixa por minuto: se virar no meio da amostra, recomeça.
	const attempts, calls = 3, 6
	for attempt := 0; attempt < attempts; attempt++ {
		prev := -1
		ok := true
		for i := 0; i < calls && ok; i++ {
			r := callAt(t, bases[i%2], http.MethodGet, "/payments/v1/payments", ana, nil, nil)
			expectStatus(t, r, http.StatusOK)
			remaining, err := strconv.Atoi(r.header.Get("RateLimit-Remaining"))
			if err != nil {
				t.Fatalf("RateLimit-Remaining = %q: %v", r.header.Get("RateLimit-Remaining"), err)
			}
			if prev != -1 && remaining != prev-1 {
				ok = false
				t.Logf("attempt %d: call %d on %s saw remaining %d after %d", attempt+1, i, bases[i%2], remaining, prev)
			}
			prev = remaining
		}
		if ok {
			return
		}
	}
	t.Fatal("remaining quota did not drop by one per call across instances: the counter is not shared")
}
