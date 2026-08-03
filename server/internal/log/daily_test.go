package log

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestDailyWriterPruneKeepsTwoDays(t *testing.T) {
	dir := t.TempDir()
	now := time.Date(2026, 8, 3, 15, 0, 0, 0, time.Local)
	today := now.Format("2006-01-02")
	yesterday := now.AddDate(0, 0, -1).Format("2006-01-02")
	older := now.AddDate(0, 0, -2).Format("2006-01-02")
	ancient := now.AddDate(0, 0, -5).Format("2006-01-02")

	for _, name := range []string{
		"hopper.log",
		"hopper-" + today + ".log",
		"hopper-" + yesterday + ".log",
		"hopper-" + older + ".log",
		"hopper-" + ancient + ".log",
		"hopper-not-a-date.log",
	} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte("x"), 0o600); err != nil {
			t.Fatal(err)
		}
	}

	w := &dailyWriter{dir: dir, keepDays: 2}
	if err := w.reopen(now); err != nil {
		t.Fatal(err)
	}
	w.prune(now)

	remain := map[string]bool{}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, ent := range entries {
		remain[ent.Name()] = true
	}

	wantKeep := []string{
		"hopper-" + today + ".log",
		"hopper-" + yesterday + ".log",
		"hopper-not-a-date.log",
	}
	wantGone := []string{
		"hopper.log",
		"hopper-" + older + ".log",
		"hopper-" + ancient + ".log",
	}
	for _, name := range wantKeep {
		if !remain[name] {
			t.Fatalf("expected to keep %s, have %#v", name, remain)
		}
	}
	for _, name := range wantGone {
		if remain[name] {
			t.Fatalf("expected to remove %s, have %#v", name, remain)
		}
	}
}

func TestDailyWriterRotatesOnDayChange(t *testing.T) {
	dir := t.TempDir()
	w := &dailyWriter{dir: dir, keepDays: 2}
	day1 := time.Date(2026, 8, 2, 23, 0, 0, 0, time.Local)
	day2 := time.Date(2026, 8, 3, 0, 1, 0, 0, time.Local)

	if err := w.reopen(day1); err != nil {
		t.Fatal(err)
	}
	if _, err := w.file.Write([]byte("day1\n")); err != nil {
		t.Fatal(err)
	}
	if err := w.reopen(day2); err != nil {
		t.Fatal(err)
	}
	if _, err := w.file.Write([]byte("day2\n")); err != nil {
		t.Fatal(err)
	}

	b1, err := os.ReadFile(filepath.Join(dir, "hopper-2026-08-02.log"))
	if err != nil {
		t.Fatal(err)
	}
	b2, err := os.ReadFile(filepath.Join(dir, "hopper-2026-08-03.log"))
	if err != nil {
		t.Fatal(err)
	}
	if string(b1) != "day1\n" || string(b2) != "day2\n" {
		t.Fatalf("got %q and %q", b1, b2)
	}
}
