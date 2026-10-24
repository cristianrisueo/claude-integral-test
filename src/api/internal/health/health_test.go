package health

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	okBody          = `{"status":"ok","database":"ok","version":"dev"}`
	unavailableBody = `{"status":"unavailable","database":"unreachable","version":"dev"}`
)

// pingFunc adapts a function to Pinger.
type pingFunc func(ctx context.Context) error

func (f pingFunc) Ping(ctx context.Context) error { return f(ctx) }

var (
	answers  = pingFunc(func(context.Context) error { return nil })
	refusals = pingFunc(func(context.Context) error { return errors.New("dial tcp 127.0.0.1:1: connect: connection refused") })
)

// get calls GET /api/health on h and returns the response and its trimmed body.
func get(t *testing.T, h http.Handler) (*http.Response, string) {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/health", nil))
	res := rec.Result()
	body, err := io.ReadAll(res.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	return res, strings.TrimSpace(string(body))
}

func assertResponse(t *testing.T, res *http.Response, body string, wantCode int, wantBody string) {
	t.Helper()
	if res.StatusCode != wantCode {
		t.Errorf("status = %d, want %d", res.StatusCode, wantCode)
	}
	if body != wantBody {
		t.Errorf("body = %q, want %q", body, wantBody)
	}
	if got := res.Header.Get("Content-Type"); got != "application/json" {
		t.Errorf("Content-Type = %q, want application/json", got)
	}
	if got := res.Header.Get("Cache-Control"); got != "no-store" {
		t.Errorf("Cache-Control = %q, want no-store", got)
	}
}

// closedPort returns a local port that nothing listens on.
func closedPort(t *testing.T) int {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	ln.Close()
	return port
}

// silentPort returns a local port that accepts connections and never answers.
func silentPort(t *testing.T) int {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	var conns []net.Conn
	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			conns = append(conns, c)
		}
	}()
	t.Cleanup(func() {
		ln.Close()
		<-done
		for _, c := range conns {
			c.Close()
		}
	})
	return ln.Addr().(*net.TCPAddr).Port
}

// pool returns a real pgx pool pointed at a local port.
func pool(t *testing.T, port int) *pgxpool.Pool {
	t.Helper()
	p, err := pgxpool.New(context.Background(),
		fmt.Sprintf("host=127.0.0.1 port=%d user=app password=app dbname=app sslmode=disable", port))
	if err != nil {
		t.Fatalf("pgxpool.New: %v", err)
	}
	t.Cleanup(p.Close)
	return p
}

// AC1
func TestHealthDatabaseReachable(t *testing.T) {
	res, body := get(t, Handler(answers, "dev"))
	assertResponse(t, res, body, http.StatusOK, okBody)
}

// AC2
func TestHealthDatabaseUnreachable(t *testing.T) {
	for name, port := range map[string]func(*testing.T) int{
		"connection refused": closedPort,
		"no answer":          silentPort,
	} {
		t.Run(name, func(t *testing.T) {
			var logs bytes.Buffer
			prev := slog.Default()
			slog.SetDefault(slog.New(slog.NewTextHandler(&logs, nil)))
			t.Cleanup(func() { slog.SetDefault(prev) })

			h := Handler(pool(t, port(t)), "dev")
			start := time.Now()
			res, body := get(t, h)
			if elapsed := time.Since(start); elapsed >= 3*time.Second {
				t.Errorf("answered in %v, want under 3s", elapsed)
			}
			// The exact body also proves that no error detail leaks into it.
			assertResponse(t, res, body, http.StatusServiceUnavailable, unavailableBody)
			if !strings.Contains(logs.String(), "level=ERROR") {
				t.Errorf("the database error was not logged; logs: %q", logs.String())
			}
		})
	}
}

// AC3
func TestHealthReportsVersion(t *testing.T) {
	res, body := get(t, Handler(answers, "abc1234"))
	assertResponse(t, res, body, http.StatusOK, `{"status":"ok","database":"ok","version":"abc1234"}`)

	res, body = get(t, Handler(refusals, "abc1234"))
	assertResponse(t, res, body, http.StatusServiceUnavailable, `{"status":"unavailable","database":"unreachable","version":"abc1234"}`)
}

// AC4
func TestHealthRecovers(t *testing.T) {
	up := false
	db := pingFunc(func(ctx context.Context) error {
		if !up {
			return refusals(ctx)
		}
		return nil
	})
	h := Handler(db, "dev")

	res, body := get(t, h)
	assertResponse(t, res, body, http.StatusServiceUnavailable, unavailableBody)

	up = true
	res, body = get(t, h)
	assertResponse(t, res, body, http.StatusOK, okBody)
}
