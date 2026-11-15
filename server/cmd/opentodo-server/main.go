// Command opentodo-server runs the sync service.
package main

import (
	"context"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"sort"
	"syscall"
	"time"

	"opentodo/server/internal/api"
	"opentodo/server/internal/store"
)

func main() {
	addr := flag.String("addr", envOr("OPENTODO_ADDR", "127.0.0.1:8686"), "listen address")
	dbPath := flag.String("db", envOr("OPENTODO_DB", "data/opentodo.db"), "SQLite database file")
	backupDir := flag.String("backup-dir", "", "write a backup of the database into this folder and exit")
	keep := flag.Int("keep", 14, "with -backup-dir: how many backups to keep")
	flag.Parse()

	log := slog.New(slog.NewJSONHandler(os.Stderr, nil))
	if *backupDir != "" {
		if err := backup(*dbPath, *backupDir, *keep); err != nil {
			log.Error("backup", "err", err)
			os.Exit(1)
		}
		return
	}
	if err := os.MkdirAll(filepath.Dir(*dbPath), 0o750); err != nil {
		log.Error("create data dir", "err", err)
		os.Exit(1)
	}
	st, err := store.Open(*dbPath)
	if err != nil {
		log.Error("open database", "err", err)
		os.Exit(1)
	}
	defer st.Close()

	srv := &http.Server{
		Addr:              *addr,
		Handler:           api.New(st, log),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       60 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdown)
	}()

	log.Info("listening", "addr", *addr, "db", *dbPath)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Error("serve", "err", err)
		os.Exit(1)
	}
}

// backup copies the database into dir as opentodo-<time>.db and removes all
// but the newest keep copies.
func backup(dbPath, dir string, keep int) error {
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return err
	}
	st, err := store.Open(dbPath)
	if err != nil {
		return err
	}
	defer st.Close()
	out := filepath.Join(dir, "opentodo-"+time.Now().UTC().Format("20060102-150405")+".db")
	if err := st.BackupTo(context.Background(), out); err != nil {
		return err
	}
	old, err := filepath.Glob(filepath.Join(dir, "opentodo-*.db"))
	if err != nil {
		return err
	}
	sort.Strings(old) // names sort by time
	for len(old) > keep {
		if err := os.Remove(old[0]); err != nil {
			return err
		}
		old = old[1:]
	}
	return nil
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
