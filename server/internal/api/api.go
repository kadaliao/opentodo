// Package api serves the HTTP JSON interface clients use to sign in and sync.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"unicode/utf8"

	"golang.org/x/crypto/bcrypt"

	"opentodo/server/internal/store"
)

const (
	maxBody         = 8 << 20 // a full first sync can be large
	maxChanges      = 1000
	maxRecordBytes  = 256 << 10
	defaultPull     = 500
	maxPull         = 2000
	minPasswordLen  = 8
	maxPasswordByte = 72 // bcrypt's limit
)

// BcryptCost is lowered by tests.
var BcryptCost = 12

// AuthPerMinute caps sign-in and sign-up attempts per client IP.
var AuthPerMinute = 10

type Server struct {
	store *store.Store
	log   *slog.Logger
	// dummyHash keeps login timing the same whether or not the email exists.
	dummyHash []byte
}

func New(st *store.Store, log *slog.Logger) http.Handler {
	h, _ := bcrypt.GenerateFromPassword([]byte("not-a-real-password"), BcryptCost)
	s := &Server{store: st, log: log, dummyHash: h}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write([]byte(homePage))
	})
	mux.HandleFunc("GET /v1/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	auth := newLimiter(AuthPerMinute, AuthPerMinute)
	mux.HandleFunc("POST /v1/auth/register", s.limited(auth, s.register))
	mux.HandleFunc("POST /v1/auth/login", s.limited(auth, s.login))
	mux.HandleFunc("POST /v1/auth/logout", s.authed(s.logout))
	mux.HandleFunc("GET /v1/me", s.authed(s.me))
	mux.HandleFunc("POST /v1/sync", s.authed(s.sync))
	return mux
}

// ---- helpers ----

type apiError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]apiError{"error": {Code: code, Message: message}})
}

func (s *Server) internal(w http.ResponseWriter, r *http.Request, err error) {
	s.log.Error("request failed", "path", r.URL.Path, "err", err)
	writeError(w, http.StatusInternalServerError, "internal", "internal error")
}

func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, maxBody)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		writeError(w, http.StatusBadRequest, "bad_request", "invalid JSON body: "+err.Error())
		return false
	}
	return true
}

type ctxKey int

const (
	userKey ctxKey = iota
	tokenKey
)

func (s *Server) authed(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok || token == "" {
			writeError(w, http.StatusUnauthorized, "unauthorized", "missing bearer token")
			return
		}
		u, err := s.store.UserForToken(r.Context(), token)
		if errors.Is(err, store.ErrNotFound) {
			writeError(w, http.StatusUnauthorized, "unauthorized", "invalid or expired token")
			return
		}
		if err != nil {
			s.internal(w, r, err)
			return
		}
		ctx := context.WithValue(r.Context(), userKey, u)
		ctx = context.WithValue(ctx, tokenKey, token)
		next(w, r.WithContext(ctx))
	}
}

func currentUser(r *http.Request) store.User { return r.Context().Value(userKey).(store.User) }

// ---- auth ----

type credentials struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	Device   string `json:"device"`
}

type authResponse struct {
	Token string   `json:"token"`
	User  userJSON `json:"user"`
}

type userJSON struct {
	ID    string `json:"id"`
	Email string `json:"email"`
}

func normalizeEmail(e string) string { return strings.ToLower(strings.TrimSpace(e)) }

func validEmail(e string) bool {
	at := strings.IndexByte(e, '@')
	return at > 0 && at < len(e)-1 && len(e) <= 254 && !strings.ContainsAny(e, " \t\r\n")
}

func (s *Server) register(w http.ResponseWriter, r *http.Request) {
	var c credentials
	if !decode(w, r, &c) {
		return
	}
	email := normalizeEmail(c.Email)
	if !validEmail(email) {
		writeError(w, http.StatusBadRequest, "invalid_email", "email address is not valid")
		return
	}
	if utf8.RuneCountInString(c.Password) < minPasswordLen || len(c.Password) > maxPasswordByte {
		writeError(w, http.StatusBadRequest, "weak_password", "password must be 8 to 72 bytes")
		return
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(c.Password), BcryptCost)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	u, err := s.store.CreateUser(r.Context(), email, string(hash))
	if errors.Is(err, store.ErrEmailTaken) {
		writeError(w, http.StatusConflict, "email_taken", "email is already registered")
		return
	}
	if err != nil {
		s.internal(w, r, err)
		return
	}
	s.issueToken(w, r, u, c.Device, http.StatusCreated)
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var c credentials
	if !decode(w, r, &c) {
		return
	}
	u, err := s.store.UserByEmail(r.Context(), normalizeEmail(c.Email))
	if err != nil && !errors.Is(err, store.ErrNotFound) {
		s.internal(w, r, err)
		return
	}
	hash := s.dummyHash
	if err == nil {
		hash = []byte(u.PasswordHash)
	}
	if bcrypt.CompareHashAndPassword(hash, []byte(c.Password)) != nil || err != nil {
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "email or password is incorrect")
		return
	}
	s.issueToken(w, r, u, c.Device, http.StatusOK)
}

func (s *Server) issueToken(w http.ResponseWriter, r *http.Request, u store.User, device string, status int) {
	if len(device) > 100 {
		device = device[:100]
	}
	token, err := s.store.CreateSession(r.Context(), u.ID, device)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, status, authResponse{Token: token, User: userJSON{ID: u.ID, Email: u.Email}})
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	if err := s.store.DeleteSession(r.Context(), r.Context().Value(tokenKey).(string)); err != nil {
		s.internal(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	u := currentUser(r)
	writeJSON(w, http.StatusOK, userJSON{ID: u.ID, Email: u.Email})
}

// ---- sync ----

type syncRequest struct {
	Cursor  int64          `json:"cursor"`
	Changes []store.Change `json:"changes"`
	Limit   int            `json:"limit"`
}

func (s *Server) sync(w http.ResponseWriter, r *http.Request) {
	var req syncRequest
	if !decode(w, r, &req) {
		return
	}
	if req.Cursor < 0 {
		writeError(w, http.StatusBadRequest, "bad_request", "cursor must not be negative")
		return
	}
	if len(req.Changes) > maxChanges {
		writeError(w, http.StatusRequestEntityTooLarge, "too_many_changes", "push at most 1000 changes per request")
		return
	}
	for i, c := range req.Changes {
		if msg := validateChange(c); msg != "" {
			writeError(w, http.StatusBadRequest, "invalid_change", "change "+itoa(i)+": "+msg)
			return
		}
	}
	limit := req.Limit
	if limit <= 0 {
		limit = defaultPull
	}
	limit = min(limit, maxPull)
	res, err := s.store.Sync(r.Context(), currentUser(r).ID, req.Cursor, req.Changes, limit)
	if err != nil {
		s.internal(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func validateChange(c store.Change) string {
	switch {
	case !store.Entities[c.Entity]:
		return "unknown entity " + strconvQuote(c.Entity)
	case c.ID == "" || len(c.ID) > 64:
		return "id must be 1 to 64 bytes"
	case c.UpdatedAt <= 0:
		return "updatedAt must be a positive millisecond timestamp"
	case len(c.Data) == 0 || len(c.Data) > maxRecordBytes:
		return "data must be a JSON object under 256 KB"
	}
	var obj map[string]json.RawMessage
	if err := json.Unmarshal(c.Data, &obj); err != nil {
		return "data must be a JSON object"
	}
	return ""
}

// homePage is what a browser sees at the root: this address is for the app,
// so say that instead of a bare 404.
const homePage = `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>同步服务</title>
<style>
  body { font: 16px/1.6 -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
         margin: 0; min-height: 100vh; display: grid; place-items: center;
         background: #f4f8f7; color: #1d2b28; }
  main { max-width: 28rem; padding: 2rem; text-align: center; }
  .dot { display: inline-block; width: .6rem; height: .6rem; border-radius: 50%;
         background: #14a38b; margin-right: .5rem; vertical-align: middle; }
  p { color: #52625e; }
  @media (prefers-color-scheme: dark) {
    body { background: #101615; color: #e3ece9; }
    p { color: #9fb1ac; }
  }
</style>
</head>
<body>
<main>
  <h1><span class="dot"></span>同步服务运行中</h1>
  <p>这个地址是 App 用来同步任务的，不是网页。在 App 里登录账号即可使用。</p>
</main>
</body>
</html>
`
