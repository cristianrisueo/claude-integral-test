// Command api serves the HTTP API on port 8080.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/cristianrisueo/claude-integral-test/src/api/internal/health"
	"github.com/jackc/pgx/v5/pgxpool"
)

// version is the git commit the binary was built from, set at link time
// with -ldflags "-X main.version=<sha>".
var version = "dev"

// addr is where the API listens.
const addr = ":8080"

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if err := run(ctx); err != nil {
		slog.Error("api stopped", "error", err)
		os.Exit(1)
	}
}

func run(ctx context.Context) error {
	srv, cleanup, err := newServer()
	if err != nil {
		return err
	}
	defer cleanup()

	ln, err := net.Listen("tcp", srv.Addr)
	if err != nil {
		return err
	}
	slog.Info("api listening", "addr", srv.Addr, "version", version)
	return serve(ctx, srv, ln)
}

// configFromEnv reads the database settings from the PG* variables
// (PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE, PGSSLMODE).
func configFromEnv() (*pgxpool.Config, error) {
	return pgxpool.ParseConfig("")
}

// newServer builds the HTTP server and returns it with a cleanup that closes
// its database pool. The pool connects lazily, so the server starts while
// the database is unreachable.
func newServer() (*http.Server, func(), error) {
	cfg, err := configFromEnv()
	if err != nil {
		return nil, nil, err
	}
	pool, err := pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		return nil, nil, err
	}

	mux := http.NewServeMux()
	mux.Handle("GET /api/health", health.Handler(pool, version))
	mux.Handle("GET /api/live", health.Live(version))

	srv := &http.Server{Addr: addr, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	return srv, pool.Close, nil
}

// serve runs srv on ln until ctx is done, then shuts it down.
func serve(ctx context.Context, srv *http.Server, ln net.Listener) error {
	errc := make(chan error, 1)
	go func() { errc <- srv.Serve(ln) }()

	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		return err
	}
	if err := <-errc; !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}
