package log

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sync"
	"time"
)

// DefaultKeepDays is how many calendar days of hopper-YYYY-MM-DD.log to retain
// (today counts as one). Default 2 keeps today and yesterday.
const DefaultKeepDays = 2

var dayLogRE = regexp.MustCompile(`^hopper-(\d{4}-\d{2}-\d{2})\.log$`)

type dailyWriter struct {
	dir      string
	keepDays int

	mu   sync.Mutex
	day  string
	file *os.File
}

// SetDailyDir writes logs to hopper-YYYY-MM-DD.log under dir, rotates at
// local midnight, and prunes files older than the keepDays retention window.
// keepDays < 1 falls back to DefaultKeepDays.
func SetDailyDir(dir string, keepDays int) error {
	if dir == "" {
		return fmt.Errorf("empty log dir")
	}
	if keepDays < 1 {
		keepDays = DefaultKeepDays
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	w := &dailyWriter{dir: dir, keepDays: keepDays}
	w.mu.Lock()
	err := w.reopen(time.Now())
	if err == nil {
		w.prune(time.Now())
	}
	w.mu.Unlock()
	if err != nil {
		return err
	}
	logSetOutput(w)
	go w.maintain()
	return nil
}

func (w *dailyWriter) Write(p []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	now := time.Now()
	if w.file == nil || w.day != localDay(now) {
		if err := w.reopen(now); err != nil {
			return 0, err
		}
		w.prune(now)
	}
	return w.file.Write(p)
}

func (w *dailyWriter) reopen(now time.Time) error {
	day := localDay(now)
	if w.file != nil {
		_ = w.file.Close()
		w.file = nil
	}
	path := filepath.Join(w.dir, fmt.Sprintf("hopper-%s.log", day))
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	w.file = f
	w.day = day
	return nil
}

func (w *dailyWriter) prune(now time.Time) {
	loc := now.Location()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)
	oldestKeep := today.AddDate(0, 0, -(w.keepDays - 1))

	_ = os.Remove(filepath.Join(w.dir, "hopper.log"))

	entries, err := os.ReadDir(w.dir)
	if err != nil {
		return
	}
	for _, ent := range entries {
		if ent.IsDir() {
			continue
		}
		m := dayLogRE.FindStringSubmatch(ent.Name())
		if m == nil {
			continue
		}
		day, err := time.ParseInLocation("2006-01-02", m[1], loc)
		if err != nil {
			continue
		}
		if day.Before(oldestKeep) {
			_ = os.Remove(filepath.Join(w.dir, ent.Name()))
		}
	}
}

func (w *dailyWriter) maintain() {
	ticker := time.NewTicker(time.Hour)
	defer ticker.Stop()
	for range ticker.C {
		w.mu.Lock()
		now := time.Now()
		if w.file == nil || w.day != localDay(now) {
			_ = w.reopen(now)
		}
		w.prune(now)
		w.mu.Unlock()
	}
}

func localDay(t time.Time) string {
	return t.Format("2006-01-02")
}
