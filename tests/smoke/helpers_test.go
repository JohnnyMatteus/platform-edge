//go:build smoke

// Package smoke contém os smoke tests das políticas de borda. Eles exigem a
// stack do docker-compose no ar (make up) e rodam com: make smoke.
package smoke

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"
)

const (
	issuer   = "http://localhost:8080/realms/edge"
	audience = "edge-gateway"
	// Senha DEV ONLY dos usuários fictícios do realm.
	devPassword = "dev-only-change-me"
	devKeyPath  = "../../keycloak/dev-keys/realm-signing.dev-only.key"
)

var (
	gatewayURL  = envOr("GATEWAY_URL", "http://localhost:8000")
	keycloakURL = envOr("KEYCLOAK_URL", "http://localhost:8080")
	httpClient  = &http.Client{Timeout: 10 * time.Second}
)

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func TestMain(m *testing.M) {
	if err := waitFor(gatewayURL+"/studios/v1/public/schedule", 90*time.Second); err != nil {
		fmt.Fprintln(os.Stderr, "gateway not ready (run `make up` first):", err)
		os.Exit(1)
	}
	if err := waitFor(keycloakURL+"/realms/edge/.well-known/openid-configuration", 90*time.Second); err != nil {
		fmt.Fprintln(os.Stderr, "keycloak not ready (run `make up` first):", err)
		os.Exit(1)
	}
	os.Exit(m.Run())
}

func waitFor(target string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	var lastErr error
	for time.Now().Before(deadline) {
		resp, err := httpClient.Get(target)
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode < 500 {
				return nil
			}
			lastErr = fmt.Errorf("status %d", resp.StatusCode)
		} else {
			lastErr = err
		}
		time.Sleep(2 * time.Second)
	}
	return lastErr
}

// passwordToken obtém um access token pelo password grant (habilitado só em dev).
func passwordToken(t *testing.T, clientID, clientSecret, username string) string {
	t.Helper()
	form := url.Values{
		"grant_type": {"password"},
		"client_id":  {clientID},
		"username":   {username},
		"password":   {devPassword},
	}
	if clientSecret != "" {
		form.Set("client_secret", clientSecret)
	}
	return requestToken(t, form)
}

// clientCredentialsToken obtém um token de service account.
func clientCredentialsToken(t *testing.T, clientID, clientSecret string) string {
	t.Helper()
	return requestToken(t, url.Values{
		"grant_type":    {"client_credentials"},
		"client_id":     {clientID},
		"client_secret": {clientSecret},
	})
}

func requestToken(t *testing.T, form url.Values) string {
	t.Helper()
	resp, err := httpClient.PostForm(keycloakURL+"/realms/edge/protocol/openid-connect/token", form)
	if err != nil {
		t.Fatalf("token request failed: %v", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("token request: status %d: %s", resp.StatusCode, body)
	}
	var tok struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.Unmarshal(body, &tok); err != nil || tok.AccessToken == "" {
		t.Fatalf("token response without access_token: %s", body)
	}
	return tok.AccessToken
}

// mintToken assina um JWT RS256 com a chave DEV ONLY do realm. Permite forjar
// tokens com claims inválidas (issuer, aud, exp) que o Keycloak nunca emitiria.
func mintToken(t *testing.T, claims map[string]any) string {
	t.Helper()
	raw, err := os.ReadFile(devKeyPath)
	if err != nil {
		t.Fatalf("read dev key: %v", err)
	}
	block, _ := pem.Decode(raw)
	if block == nil {
		t.Fatal("dev key is not PEM")
	}
	key, err := x509.ParsePKCS1PrivateKey(block.Bytes)
	if err != nil {
		t.Fatalf("parse dev key: %v", err)
	}

	enc := base64.RawURLEncoding
	header, _ := json.Marshal(map[string]string{"alg": "RS256", "typ": "JWT"})
	payload, err := json.Marshal(claims)
	if err != nil {
		t.Fatalf("marshal claims: %v", err)
	}
	signingInput := enc.EncodeToString(header) + "." + enc.EncodeToString(payload)
	digest := sha256.Sum256([]byte(signingInput))
	sig, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, digest[:])
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	return signingInput + "." + enc.EncodeToString(sig)
}

// validClaims devolve claims equivalentes às de um token do Keycloak.
func validClaims(azp string, roles ...string) map[string]any {
	now := time.Now().Unix()
	return map[string]any{
		"iss":          issuer,
		"aud":          audience,
		"sub":          "forged-subject",
		"azp":          azp,
		"iat":          now,
		"exp":          now + 300,
		"realm_access": map[string]any{"roles": roles},
	}
}

type response struct {
	status int
	header http.Header
	body   []byte
}

func call(t *testing.T, method, path, token string, body io.Reader, headers map[string]string) response {
	t.Helper()
	req, err := http.NewRequest(method, gatewayURL+path, body)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, path, err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return response{status: resp.StatusCode, header: resp.Header, body: b}
}

func expectStatus(t *testing.T, r response, want int) {
	t.Helper()
	if r.status != want {
		t.Fatalf("status = %d, want %d; body: %s", r.status, want, strings.TrimSpace(string(r.body)))
	}
}
