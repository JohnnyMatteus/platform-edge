// Command upstream-stub sobe um upstream HTTP fictício usado no ambiente
// local para imitar os serviços protegidos pelo gateway.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/JohnnyMatteus/platform-edge/internal/stub"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	// A imagem distroless não tem shell nem curl: o healthcheck do compose
	// chama o próprio binário.
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		if err := healthcheck(); err != nil {
			logger.Error("healthcheck failed", "error", err.Error())
			os.Exit(1)
		}
		return
	}
	if err := run(logger); err != nil {
		logger.Error("upstream-stub stopped", "error", err.Error())
		os.Exit(1)
	}
}

func run(logger *slog.Logger) error {
	service := os.Getenv("SERVICE_NAME")
	if service == "" {
		return errors.New("SERVICE_NAME is required")
	}
	addr := ":" + envOr("PORT", "8080")
	logger = logger.With("service", service)

	srv := &http.Server{
		Addr:              addr,
		Handler:           stub.NewHandler(service, logger, time.Now),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	errCh := make(chan error, 1)
	go func() {
		logger.Info("upstream-stub listening", "addr", addr)
		errCh <- srv.ListenAndServe()
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return srv.Shutdown(shutdownCtx)
	}
}

func healthcheck() error {
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get("http://127.0.0.1:" + envOr("PORT", "8080") + "/healthz")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status %d", resp.StatusCode)
	}
	return nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
