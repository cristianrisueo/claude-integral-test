// Package health serves GET /api/health: whether PostgreSQL answers, and the
// build version of the API.
package health

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"
)

// pingTimeout bounds the database ping, so the check answers in under 3s.
const pingTimeout = 2 * time.Second

// Pinger is the one thing the handler needs from the database.
// *pgxpool.Pool satisfies it.
type Pinger interface {
	Ping(ctx context.Context) error
}

type response struct {
	Status   string `json:"status"`
	Database string `json:"database"`
	Version  string `json:"version"`
}

// Handler answers the health check with the given build version. It pings
// the database on every call, so it reports a recovered database at once.
// The ping error goes to the log, never to the response.
func Handler(db Pinger, version string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), pingTimeout)
		defer cancel()

		code, body := http.StatusOK, response{Status: "ok", Database: "ok", Version: version}
		if err := db.Ping(ctx); err != nil {
			slog.ErrorContext(r.Context(), "health: database ping failed", "error", err)
			code, body = http.StatusServiceUnavailable, response{Status: "unavailable", Database: "unreachable", Version: version}
		}

		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		w.WriteHeader(code)
		if err := json.NewEncoder(w).Encode(body); err != nil {
			slog.ErrorContext(r.Context(), "health: write response", "error", err)
		}
	})
}
