package health

import "net/http"

// Live answers GET /api/live. Stub: not implemented yet.
func Live(version string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	})
}
