package config

import "testing"

func env(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

func TestLoadDefaults(t *testing.T) {
	c, err := Load(env(nil))
	if err != nil {
		t.Fatal(err)
	}
	if c.ListenAddr != "127.0.0.1:8080" {
		t.Fatalf("unexpected default addr %q", c.ListenAddr)
	}
}

func TestLoadOverride(t *testing.T) {
	c, err := Load(env(map[string]string{"SECUREVAULT_ADDR": ":9000", "DATABASE_URL": "x"}))
	if err != nil || c.ListenAddr != ":9000" || c.DatabaseURL != "x" {
		t.Fatalf("got %+v, %v", c, err)
	}
}

func TestLoadInvalidAddr(t *testing.T) {
	if _, err := Load(env(map[string]string{"SECUREVAULT_ADDR": "nonsense"})); err == nil {
		t.Fatal("expected error")
	}
}
