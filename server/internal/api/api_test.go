package api_test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"opentodo/server/internal/api"
	"opentodo/server/internal/store"
)

func newServer(t *testing.T) *httptest.Server {
	t.Helper()
	api.BcryptCost = 4 // the minimum; keeps tests fast
	st, err := store.Open(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	srv := httptest.NewServer(api.New(st, slog.New(slog.NewTextHandler(io.Discard, nil))))
	t.Cleanup(srv.Close)
	return srv
}

type client struct {
	t     *testing.T
	base  string
	token string
}

func (c *client) do(method, path string, body any, out any) int {
	c.t.Helper()
	var r io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		r = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, c.base+path, r)
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		c.t.Fatal(err)
	}
	defer resp.Body.Close()
	if out != nil && resp.StatusCode < 300 && resp.StatusCode != http.StatusNoContent {
		if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
			c.t.Fatalf("%s %s: decode: %v", method, path, err)
		}
	}
	return resp.StatusCode
}

func register(t *testing.T, srv *httptest.Server, email string) *client {
	t.Helper()
	c := &client{t: t, base: srv.URL}
	var res struct{ Token string }
	if code := c.do("POST", "/v1/auth/register", map[string]string{"email": email, "password": "correct horse"}, &res); code != 201 {
		t.Fatalf("register: %d", code)
	}
	c.token = res.Token
	return c
}

func login(t *testing.T, srv *httptest.Server, email string) *client {
	t.Helper()
	c := &client{t: t, base: srv.URL}
	var res struct{ Token string }
	if code := c.do("POST", "/v1/auth/login", map[string]string{"email": email, "password": "correct horse"}, &res); code != 200 {
		t.Fatalf("login: %d", code)
	}
	c.token = res.Token
	return c
}

type change = store.Change

func task(id string, updatedAt int64, title string) change {
	return change{Entity: "task", ID: id, UpdatedAt: updatedAt, Data: json.RawMessage(fmt.Sprintf(`{"title":%q}`, title))}
}

type syncRes struct {
	Accepted []store.Accepted
	Changes  []store.Record
	Cursor   int64
	HasMore  bool
}

func (c *client) sync(cursor int64, changes ...change) syncRes {
	c.t.Helper()
	var res syncRes
	if code := c.do("POST", "/v1/sync", map[string]any{"cursor": cursor, "changes": changes}, &res); code != 200 {
		c.t.Fatalf("sync: %d", code)
	}
	return res
}

func titles(rs []store.Record) []string {
	var out []string
	for _, r := range rs {
		var d struct{ Title string }
		_ = json.Unmarshal(r.Data, &d)
		out = append(out, d.Title)
	}
	return out
}

func TestRegisterAndLogin(t *testing.T) {
	srv := newServer(t)
	anon := &client{t: t, base: srv.URL}

	for _, tc := range []struct {
		email, password string
		want            int
	}{
		{"not-an-email", "correct horse", 400},
		{"a@b.co", "short", 400},
		{"A@Example.com ", "correct horse", 201},
		{"a@example.com", "correct horse", 409}, // same address, different case
	} {
		if got := anon.do("POST", "/v1/auth/register", map[string]string{"email": tc.email, "password": tc.password}, nil); got != tc.want {
			t.Errorf("register(%q, %q) = %d, want %d", tc.email, tc.password, got, tc.want)
		}
	}

	if got := anon.do("POST", "/v1/auth/login", map[string]string{"email": "a@example.com", "password": "wrong password"}, nil); got != 401 {
		t.Errorf("wrong password: %d", got)
	}
	if got := anon.do("POST", "/v1/auth/login", map[string]string{"email": "nobody@example.com", "password": "correct horse"}, nil); got != 401 {
		t.Errorf("unknown email: %d", got)
	}

	c := login(t, srv, "a@example.com")
	var me struct{ Email string }
	if code := c.do("GET", "/v1/me", nil, &me); code != 200 || me.Email != "a@example.com" {
		t.Fatalf("me: %d %+v", code, me)
	}
	if code := c.do("POST", "/v1/auth/logout", nil, nil); code != 204 {
		t.Fatalf("logout: %d", code)
	}
	if code := c.do("GET", "/v1/me", nil, nil); code != 401 {
		t.Fatalf("token still works after logout: %d", code)
	}
}

func TestSyncNeedsAToken(t *testing.T) {
	srv := newServer(t)
	anon := &client{t: t, base: srv.URL}
	if code := anon.do("POST", "/v1/sync", map[string]any{"cursor": 0}, nil); code != 401 {
		t.Fatalf("got %d", code)
	}
	anon.token = "made-up"
	if code := anon.do("POST", "/v1/sync", map[string]any{"cursor": 0}, nil); code != 401 {
		t.Fatalf("got %d", code)
	}
}

func TestTwoDevicesSync(t *testing.T) {
	srv := newServer(t)
	phone := register(t, srv, "me@example.com")
	mac := login(t, srv, "me@example.com")

	res := phone.sync(0, task("t1", 100, "买菜"), task("t2", 100, "开会"))
	if len(res.Accepted) != 2 || len(res.Changes) != 0 || res.Cursor != 2 {
		t.Fatalf("phone push: %+v", res)
	}
	phoneCursor := res.Cursor

	res = mac.sync(0)
	if got := titles(res.Changes); fmt.Sprint(got) != "[买菜 开会]" || res.Cursor != 2 {
		t.Fatalf("mac pull: %v cursor %d", got, res.Cursor)
	}
	macCursor := res.Cursor

	// Nothing new: an empty pull keeps the cursor.
	if res = mac.sync(macCursor); len(res.Changes) != 0 || res.Cursor != 2 {
		t.Fatalf("empty pull: %+v", res)
	}

	// The Mac renames a task; the phone sees it, and isn't sent its own pushes back.
	res = mac.sync(macCursor, task("t1", 200, "买菜和水果"))
	macCursor = res.Cursor
	res = phone.sync(phoneCursor, task("t3", 150, "健身"))
	if got := titles(res.Changes); fmt.Sprint(got) != "[买菜和水果]" {
		t.Fatalf("phone pull: %v", got)
	}
	if res.Cursor != 4 {
		t.Fatalf("cursor %d, want 4", res.Cursor)
	}
	if got := titles(mac.sync(macCursor).Changes); fmt.Sprint(got) != "[健身]" {
		t.Fatalf("mac pull: %v", got)
	}
}

func TestNewerEditWins(t *testing.T) {
	srv := newServer(t)
	a := register(t, srv, "me@example.com")
	b := login(t, srv, "me@example.com")

	a.sync(0, task("t1", 100, "v1"))
	b.sync(0, task("t1", 300, "from b"))

	// A edited offline earlier than B: its push loses, and it gets B's copy back
	// even though its cursor is already past that version.
	res := a.sync(2, task("t1", 200, "from a"))
	if len(res.Accepted) != 0 {
		t.Fatalf("stale edit accepted: %+v", res.Accepted)
	}
	if got := titles(res.Changes); fmt.Sprint(got) != "[from b]" {
		t.Fatalf("expected the newer copy back, got %v", got)
	}

	// A later edit from A wins.
	res = a.sync(2, task("t1", 400, "from a again"))
	if len(res.Accepted) != 1 || res.Accepted[0].Version != 3 {
		t.Fatalf("newer edit: %+v", res)
	}
	if got := titles(b.sync(2).Changes); fmt.Sprint(got) != "[from a again]" {
		t.Fatalf("b pull: %v", got)
	}
}

func TestDeletesPropagate(t *testing.T) {
	srv := newServer(t)
	a := register(t, srv, "me@example.com")
	b := login(t, srv, "me@example.com")
	a.sync(0, task("t1", 100, "x"))
	cursor := b.sync(0).Cursor

	gone := task("t1", 200, "x")
	deleted := int64(200)
	gone.DeletedAt = &deleted
	a.sync(1, gone)

	res := b.sync(cursor)
	if len(res.Changes) != 1 || res.Changes[0].DeletedAt == nil || *res.Changes[0].DeletedAt != 200 {
		t.Fatalf("tombstone not delivered: %+v", res.Changes)
	}
}

func TestPullPages(t *testing.T) {
	srv := newServer(t)
	a := register(t, srv, "me@example.com")
	var changes []change
	for i := range 5 {
		changes = append(changes, task(fmt.Sprintf("t%d", i), 100, fmt.Sprintf("task %d", i)))
	}
	a.sync(0, changes...)

	b := login(t, srv, "me@example.com")
	var got []string
	cursor := int64(0)
	for pages := 0; ; pages++ {
		var res syncRes
		b.do("POST", "/v1/sync", map[string]any{"cursor": cursor, "limit": 2}, &res)
		got = append(got, titles(res.Changes)...)
		cursor = res.Cursor
		if !res.HasMore {
			if pages != 2 {
				t.Errorf("took %d extra pages, want 2", pages)
			}
			break
		}
	}
	if fmt.Sprint(got) != "[task 0 task 1 task 2 task 3 task 4]" || cursor != 5 {
		t.Fatalf("pages: %v cursor %d", got, cursor)
	}
}

func TestUsersAreIsolated(t *testing.T) {
	srv := newServer(t)
	a := register(t, srv, "a@example.com")
	b := register(t, srv, "b@example.com")
	a.sync(0, task("t1", 100, "a's secret"))
	b.sync(0, task("t1", 50, "b's own")) // same id, different user: no conflict
	if res := b.sync(0); fmt.Sprint(titles(res.Changes)) != "[b's own]" {
		t.Fatalf("b sees %v", titles(res.Changes))
	}
	if res := a.sync(0); fmt.Sprint(titles(res.Changes)) != "[a's secret]" {
		t.Fatalf("a sees %v", titles(res.Changes))
	}
}

func TestInvalidChangesAreRejected(t *testing.T) {
	srv := newServer(t)
	a := register(t, srv, "me@example.com")
	for name, c := range map[string]change{
		"unknown entity": {Entity: "user", ID: "x", UpdatedAt: 1, Data: json.RawMessage(`{}`)},
		"empty id":       {Entity: "task", ID: "", UpdatedAt: 1, Data: json.RawMessage(`{}`)},
		"no timestamp":   {Entity: "task", ID: "x", UpdatedAt: 0, Data: json.RawMessage(`{}`)},
		"not an object":  {Entity: "task", ID: "x", UpdatedAt: 1, Data: json.RawMessage(`[1]`)},
	} {
		if code := a.do("POST", "/v1/sync", map[string]any{"cursor": 0, "changes": []change{c}}, nil); code != 400 {
			t.Errorf("%s: got %d, want 400", name, code)
		}
	}
	// A rejected request stores nothing.
	if res := a.sync(0); len(res.Changes) != 0 || res.Cursor != 0 {
		t.Fatalf("something was stored: %+v", res)
	}
}

func TestEfficiencyRecordsSync(t *testing.T) {
	srv := newServer(t)
	phone := register(t, srv, "me@example.com")
	mac := login(t, srv, "me@example.com")
	var sent []change
	for i, entity := range []string{"habit", "checkin", "focus", "countdown"} {
		sent = append(sent, change{Entity: entity, ID: entity + "-1", UpdatedAt: int64(100 + i), Data: json.RawMessage(`{"name":"x"}`)})
	}
	if res := phone.sync(0, sent...); len(res.Accepted) != 4 {
		t.Fatalf("accepted %d of 4", len(res.Accepted))
	}
	got := map[string]bool{}
	for _, r := range mac.sync(0).Changes {
		got[r.Entity+"/"+r.ID] = true
	}
	for _, c := range sent {
		if !got[c.Entity+"/"+c.ID] {
			t.Errorf("%s/%s did not arrive", c.Entity, c.ID)
		}
	}
}

func TestSignInAttemptsAreLimited(t *testing.T) {
	srv := newServer(t)
	anon := &client{t: t, base: srv.URL}
	limited := 0
	for range api.AuthPerMinute + 3 {
		code := anon.do("POST", "/v1/auth/login", map[string]string{"email": "x@example.com", "password": "wrong password"}, nil)
		if code == http.StatusTooManyRequests {
			limited++
		}
	}
	if limited != 3 {
		t.Fatalf("%d of %d attempts limited, want 3", limited, api.AuthPerMinute+3)
	}
}

func TestForwardedForIsTrustedOnlyFromLoopback(t *testing.T) {
	srv := newServer(t)
	// Each request claims a different client, but the test server sees a
	// loopback peer, so the header decides; behind Caddy that's the real IP.
	for i := range api.AuthPerMinute + 3 {
		req, _ := http.NewRequest("POST", srv.URL+"/v1/auth/login",
			bytes.NewReader([]byte(`{"email":"x@example.com","password":"wrong password"}`)))
		req.Header.Set("X-Forwarded-For", fmt.Sprintf("203.0.113.%d", i))
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode == http.StatusTooManyRequests {
			t.Fatalf("request %d from a distinct client was limited", i)
		}
	}
}

func TestRootExplainsItself(t *testing.T) {
	srv := newServer(t)
	resp, err := http.Get(srv.URL + "/")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 || !bytes.Contains(body, []byte("同步服务运行中")) {
		t.Fatalf("GET /: %d %q", resp.StatusCode, body)
	}
	// Other unknown paths are still 404.
	resp, err = http.Get(srv.URL + "/nope")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 404 {
		t.Fatalf("GET /nope: %d", resp.StatusCode)
	}
}
