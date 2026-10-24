package health

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

const liveBody = `{"status":"ok","version":"dev"}`

// liveness AC1
func TestLiveAnswersOK(t *testing.T) {
	res, body := get(t, Live("dev"))
	assertResponse(t, res, body, http.StatusOK, liveBody)
}

// liveness AC2
func TestLiveIgnoresDatabase(t *testing.T) {
	for name, port := range map[string]func(*testing.T) int{
		"connection refused": closedPort,
		"no answer":          silentPort,
	} {
		t.Run(name, func(t *testing.T) {
			mux := http.NewServeMux()
			mux.Handle("GET /api/health", Handler(pool(t, port(t)), "dev"))
			mux.Handle("GET /api/live", Live("dev"))
			srv := httptest.NewServer(mux)
			t.Cleanup(srv.Close)
			client := &http.Client{Timeout: 5 * time.Second}

			start := time.Now()
			res, err := client.Get(srv.URL + "/api/live")
			if err != nil {
				t.Fatalf("GET /api/live: %v", err)
			}
			if elapsed := time.Since(start); elapsed >= time.Second {
				t.Errorf("/api/live answered in %v, want under 1s", elapsed)
			}
			body := readBody(t, res)
			assertResponse(t, res, body, http.StatusOK, liveBody)

			res, err = client.Get(srv.URL + "/api/health")
			if err != nil {
				t.Fatalf("GET /api/health: %v", err)
			}
			body = readBody(t, res)
			if res.StatusCode != http.StatusServiceUnavailable {
				t.Errorf("/api/health status = %d, want 503; body %q", res.StatusCode, body)
			}
		})
	}
}

// liveness AC3
func TestLiveReportsVersion(t *testing.T) {
	res, body := get(t, Live("abc1234"))
	assertResponse(t, res, body, http.StatusOK, `{"status":"ok","version":"abc1234"}`)
}

// readBody reads and closes res.Body and returns it trimmed.
func readBody(t *testing.T, res *http.Response) string {
	t.Helper()
	defer res.Body.Close()
	b, err := io.ReadAll(res.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	return strings.TrimSpace(string(b))
}
