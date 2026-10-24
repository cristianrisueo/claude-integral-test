package main

import (
	"context"
	"io"
	"net"
	"net/http"
	"strconv"
	"strings"
	"testing"
	"time"
)

// AC5
func TestServerStartsWithoutDatabase(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	dbPort := ln.Addr().(*net.TCPAddr).Port
	ln.Close() // nothing listens on dbPort now

	t.Setenv("PGHOST", "127.0.0.1")
	t.Setenv("PGPORT", strconv.Itoa(dbPort))
	t.Setenv("PGUSER", "app")
	t.Setenv("PGPASSWORD", "app")
	t.Setenv("PGDATABASE", "app")
	t.Setenv("PGSSLMODE", "disable")

	srv, cleanup, err := newServer()
	if err != nil {
		t.Fatalf("newServer with the database down: %v", err)
	}
	t.Cleanup(cleanup)
	if srv.Addr != ":8080" {
		t.Errorf("server address = %q, want :8080", srv.Addr)
	}

	// Serve the same server on a free port, so the test also passes while
	// the local stack holds 8080.
	ln, err = net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- serve(ctx, srv, ln) }()
	t.Cleanup(func() {
		cancel()
		if err := <-done; err != nil {
			t.Errorf("serve: %v", err)
		}
	})

	client := &http.Client{Timeout: 5 * time.Second}
	res, err := client.Get("http://" + ln.Addr().String() + "/api/health")
	if err != nil {
		t.Fatalf("GET /api/health: %v", err)
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(res.Body)
	if res.StatusCode != http.StatusServiceUnavailable {
		t.Errorf("status = %d, want 503; body %q", res.StatusCode, body)
	}
}

// liveness AC4
func TestLiveWithoutDatabase(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	dbPort := ln.Addr().(*net.TCPAddr).Port
	ln.Close() // nothing listens on dbPort now

	t.Setenv("PGHOST", "127.0.0.1")
	t.Setenv("PGPORT", strconv.Itoa(dbPort))
	t.Setenv("PGUSER", "app")
	t.Setenv("PGPASSWORD", "app")
	t.Setenv("PGDATABASE", "app")
	t.Setenv("PGSSLMODE", "disable")

	srv, cleanup, err := newServer()
	if err != nil {
		t.Fatalf("newServer with the database down: %v", err)
	}
	t.Cleanup(cleanup)

	ln, err = net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- serve(ctx, srv, ln) }()
	t.Cleanup(func() {
		cancel()
		if err := <-done; err != nil {
			t.Errorf("serve: %v", err)
		}
	})

	client := &http.Client{Timeout: 5 * time.Second}
	res, err := client.Get("http://" + ln.Addr().String() + "/api/live")
	if err != nil {
		t.Fatalf("GET /api/live: %v", err)
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(res.Body)
	if res.StatusCode != http.StatusOK {
		t.Errorf("status = %d, want 200; body %q", res.StatusCode, body)
	}
	if got, want := strings.TrimSpace(string(body)), `{"status":"ok","version":"dev"}`; got != want {
		t.Errorf("body = %q, want %q", got, want)
	}
}

// AC6
func TestConfigFromEnvironment(t *testing.T) {
	t.Setenv("PGHOST", "db.example.internal")
	t.Setenv("PGPORT", "6543")
	t.Setenv("PGUSER", "alice")
	t.Setenv("PGPASSWORD", "s3cret")
	t.Setenv("PGDATABASE", "appdb")

	t.Run("sslmode disable", func(t *testing.T) {
		t.Setenv("PGSSLMODE", "disable")
		cfg, err := configFromEnv()
		if err != nil {
			t.Fatalf("configFromEnv: %v", err)
		}
		c := cfg.ConnConfig
		if c.Host != "db.example.internal" || c.Port != 6543 || c.User != "alice" || c.Password != "s3cret" || c.Database != "appdb" {
			t.Errorf("config = host %q port %d user %q password %q database %q, want db.example.internal 6543 alice s3cret appdb",
				c.Host, c.Port, c.User, c.Password, c.Database)
		}
		if c.TLSConfig != nil {
			t.Error("TLS is on, want off with PGSSLMODE=disable")
		}
	})

	t.Run("sslmode require", func(t *testing.T) {
		t.Setenv("PGSSLMODE", "require")
		cfg, err := configFromEnv()
		if err != nil {
			t.Fatalf("configFromEnv: %v", err)
		}
		if cfg.ConnConfig.TLSConfig == nil {
			t.Error("TLS is off, want on with PGSSLMODE=require")
		}
		if len(cfg.ConnConfig.Fallbacks) != 0 {
			t.Error("a plaintext fallback exists, want none with PGSSLMODE=require")
		}
	})
}
