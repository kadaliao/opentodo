// Package store keeps users, sessions and synced records in SQLite.
//
// Every record belongs to one user and carries a version taken from that
// user's own counter (users.seq), so a client can ask for "everything after
// version N" and get each change exactly once, in order.
package store

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	_ "modernc.org/sqlite"
)

var (
	ErrNotFound   = errors.New("store: not found")
	ErrEmailTaken = errors.New("store: email already registered")
)

// Entities lists the record types clients may sync.
var Entities = map[string]bool{"list": true, "task": true, "checklist": true, "filter": true}

type Store struct {
	db  *sql.DB
	now func() time.Time
}

// Open opens (creating if needed) the database at path and brings its schema
// up to date.
func Open(path string) (*Store, error) {
	dsn := "file:" + path +
		"?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)" +
		"&_pragma=foreign_keys(1)&_pragma=synchronous(NORMAL)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	// One connection serialises writers; SQLite allows only one at a time
	// anyway, and this avoids SQLITE_BUSY between our own goroutines.
	db.SetMaxOpenConns(1)
	s := &Store{db: db, now: time.Now}
	if err := s.migrate(context.Background()); err != nil {
		db.Close()
		return nil, fmt.Errorf("migrate: %w", err)
	}
	return s, nil
}

func (s *Store) Close() error { return s.db.Close() }

// BackupTo writes a consistent copy of the database to path (which must not
// exist). Safe while the server is running.
func (s *Store) BackupTo(ctx context.Context, path string) error {
	_, err := s.db.ExecContext(ctx, `VACUUM INTO ?`, path)
	return err
}

// SetClock replaces the clock (for tests).
func (s *Store) SetClock(now func() time.Time) { s.now = now }

var migrations = []string{
	`CREATE TABLE users (
		id TEXT PRIMARY KEY,
		email TEXT NOT NULL UNIQUE COLLATE NOCASE,
		password_hash TEXT NOT NULL,
		created_at INTEGER NOT NULL,
		seq INTEGER NOT NULL DEFAULT 0
	);
	CREATE TABLE sessions (
		token_hash TEXT PRIMARY KEY,
		user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		device TEXT NOT NULL DEFAULT '',
		created_at INTEGER NOT NULL,
		last_used_at INTEGER NOT NULL
	);
	CREATE INDEX sessions_user ON sessions(user_id);
	CREATE TABLE records (
		user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		entity TEXT NOT NULL,
		id TEXT NOT NULL,
		data TEXT NOT NULL,
		updated_at INTEGER NOT NULL,
		deleted_at INTEGER,
		version INTEGER NOT NULL,
		PRIMARY KEY (user_id, entity, id)
	);
	CREATE INDEX records_version ON records(user_id, version);`,
}

func (s *Store) migrate(ctx context.Context) error {
	var v int
	if err := s.db.QueryRowContext(ctx, `PRAGMA user_version`).Scan(&v); err != nil {
		return err
	}
	for ; v < len(migrations); v++ {
		tx, err := s.db.BeginTx(ctx, nil)
		if err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, migrations[v]); err != nil {
			tx.Rollback()
			return fmt.Errorf("migration %d: %w", v+1, err)
		}
		if _, err := tx.ExecContext(ctx, fmt.Sprintf(`PRAGMA user_version = %d`, v+1)); err != nil {
			tx.Rollback()
			return err
		}
		if err := tx.Commit(); err != nil {
			return err
		}
	}
	return nil
}

// ---- users and sessions ----

type User struct {
	ID           string
	Email        string
	PasswordHash string
	CreatedAt    time.Time
}

func randomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic(err) // crypto/rand never fails on supported platforms
	}
	return hex.EncodeToString(b)
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func (s *Store) CreateUser(ctx context.Context, email, passwordHash string) (User, error) {
	u := User{ID: randomHex(16), Email: email, PasswordHash: passwordHash, CreatedAt: s.now()}
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO users (id, email, password_hash, created_at) VALUES (?, ?, ?, ?)`,
		u.ID, u.Email, u.PasswordHash, u.CreatedAt.UnixMilli())
	if err != nil {
		var exists int
		if s.db.QueryRowContext(ctx, `SELECT 1 FROM users WHERE email = ?`, email).Scan(&exists) == nil {
			return User{}, ErrEmailTaken
		}
		return User{}, err
	}
	return u, nil
}

func (s *Store) scanUser(row *sql.Row) (User, error) {
	var u User
	var created int64
	if err := row.Scan(&u.ID, &u.Email, &u.PasswordHash, &created); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return User{}, ErrNotFound
		}
		return User{}, err
	}
	u.CreatedAt = time.UnixMilli(created)
	return u, nil
}

func (s *Store) UserByEmail(ctx context.Context, email string) (User, error) {
	return s.scanUser(s.db.QueryRowContext(ctx,
		`SELECT id, email, password_hash, created_at FROM users WHERE email = ?`, email))
}

// CreateSession returns a new bearer token. Only its hash is stored.
func (s *Store) CreateSession(ctx context.Context, userID, device string) (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	token := base64.RawURLEncoding.EncodeToString(b)
	now := s.now().UnixMilli()
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO sessions (token_hash, user_id, device, created_at, last_used_at) VALUES (?, ?, ?, ?, ?)`,
		hashToken(token), userID, device, now, now)
	if err != nil {
		return "", err
	}
	return token, nil
}

// UserForToken resolves a bearer token and records that it was used.
func (s *Store) UserForToken(ctx context.Context, token string) (User, error) {
	h := hashToken(token)
	u, err := s.scanUser(s.db.QueryRowContext(ctx,
		`SELECT u.id, u.email, u.password_hash, u.created_at
		   FROM sessions s JOIN users u ON u.id = s.user_id
		  WHERE s.token_hash = ?`, h))
	if err != nil {
		return User{}, err
	}
	_, _ = s.db.ExecContext(ctx, `UPDATE sessions SET last_used_at = ? WHERE token_hash = ?`,
		s.now().UnixMilli(), h)
	return u, nil
}

func (s *Store) DeleteSession(ctx context.Context, token string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM sessions WHERE token_hash = ?`, hashToken(token))
	return err
}

// ---- sync ----

// Change is one record as a client sends it.
type Change struct {
	Entity    string          `json:"entity"`
	ID        string          `json:"id"`
	UpdatedAt int64           `json:"updatedAt"`
	DeletedAt *int64          `json:"deletedAt"`
	Data      json.RawMessage `json:"data"`
}

// Record is a stored change with the version the server gave it.
type Record struct {
	Change
	Version int64 `json:"version"`
}

type Accepted struct {
	Entity  string `json:"entity"`
	ID      string `json:"id"`
	Version int64  `json:"version"`
}

type SyncResult struct {
	// Accepted lists the pushed changes the server stored.
	Accepted []Accepted `json:"accepted"`
	// Changes holds what the client hasn't seen: records after its cursor,
	// plus the current server copy of any pushed change that lost to a newer
	// one (so the client can drop its stale edit).
	Changes []Record `json:"changes"`
	Cursor  int64    `json:"cursor"`
	HasMore bool     `json:"hasMore"`
}

// Sync stores the pushed changes (newest updatedAt wins; ties go to the push)
// and returns the records after cursor, at most limit of them.
func (s *Store) Sync(ctx context.Context, userID string, cursor int64, changes []Change, limit int) (*SyncResult, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	res := &SyncResult{Accepted: []Accepted{}, Changes: []Record{}}

	// Read first, so a change pushed in this request isn't echoed back.
	rows, err := tx.QueryContext(ctx,
		`SELECT entity, id, data, updated_at, deleted_at, version
		   FROM records WHERE user_id = ? AND version > ?
		  ORDER BY version LIMIT ?`, userID, cursor, limit+1)
	if err != nil {
		return nil, err
	}
	seen := map[[2]string]bool{}
	for rows.Next() {
		r, err := scanRecord(rows)
		if err != nil {
			rows.Close()
			return nil, err
		}
		if len(res.Changes) == limit {
			res.HasMore = true
			break
		}
		res.Changes = append(res.Changes, r)
		seen[[2]string{r.Entity, r.ID}] = true
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}

	for _, c := range changes {
		var curUpdated, curVersion int64
		err := tx.QueryRowContext(ctx,
			`SELECT updated_at, version FROM records WHERE user_id = ? AND entity = ? AND id = ?`,
			userID, c.Entity, c.ID).Scan(&curUpdated, &curVersion)
		switch {
		case err == nil && curUpdated > c.UpdatedAt:
			// Stale push: hand back the newer copy unless it's already going out.
			if !seen[[2]string{c.Entity, c.ID}] {
				r, err := scanRecord(tx.QueryRowContext(ctx,
					`SELECT entity, id, data, updated_at, deleted_at, version
					   FROM records WHERE user_id = ? AND entity = ? AND id = ?`,
					userID, c.Entity, c.ID))
				if err != nil {
					return nil, err
				}
				res.Changes = append(res.Changes, r)
				seen[[2]string{c.Entity, c.ID}] = true
			}
			continue
		case err != nil && !errors.Is(err, sql.ErrNoRows):
			return nil, err
		}

		var version int64
		if err := tx.QueryRowContext(ctx,
			`UPDATE users SET seq = seq + 1 WHERE id = ? RETURNING seq`, userID).Scan(&version); err != nil {
			return nil, err
		}
		_, err = tx.ExecContext(ctx,
			`INSERT INTO records (user_id, entity, id, data, updated_at, deleted_at, version)
			 VALUES (?, ?, ?, ?, ?, ?, ?)
			 ON CONFLICT (user_id, entity, id) DO UPDATE SET
			   data = excluded.data, updated_at = excluded.updated_at,
			   deleted_at = excluded.deleted_at, version = excluded.version`,
			userID, c.Entity, c.ID, string(c.Data), c.UpdatedAt, c.DeletedAt, version)
		if err != nil {
			return nil, err
		}
		res.Accepted = append(res.Accepted, Accepted{Entity: c.Entity, ID: c.ID, Version: version})
	}

	if res.HasMore {
		// Stop at the last record sent; the rest come next time.
		res.Cursor = res.Changes[limit-1].Version
	} else if err := tx.QueryRowContext(ctx,
		`SELECT seq FROM users WHERE id = ?`, userID).Scan(&res.Cursor); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return res, nil
}

type scanner interface{ Scan(dest ...any) error }

func scanRecord(row scanner) (Record, error) {
	var r Record
	var data string
	var deleted sql.NullInt64
	if err := row.Scan(&r.Entity, &r.ID, &data, &r.UpdatedAt, &deleted, &r.Version); err != nil {
		return Record{}, err
	}
	r.Data = json.RawMessage(data)
	if deleted.Valid {
		v := deleted.Int64
		r.DeletedAt = &v
	}
	return r, nil
}
