package health

import (
	"encoding/json"
	"log/slog"
	"net/http"
)

type liveResponse struct {
	Status  string `json:"status"`
	Version string `json:"version"`
}

// Live answers GET /api/live with the given build version: 200 whenever the
// process can serve HTTP. It never contacts the database, so the load
// balancer can check it without a database outage marking the task unhealthy.
func Live(version string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		w.WriteHeader(http.StatusOK)
		if err := json.NewEncoder(w).Encode(liveResponse{Status: "ok", Version: version}); err != nil {
			slog.ErrorContext(r.Context(), "live: write response", "error", err)
		}
	})
}
