package hopper

import (
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"sync"
	"time"
)

type SessionInfo struct {
	ClientAddr  string    `json:"client_addr,omitempty"`
	DeviceID    string    `json:"device_id,omitempty"`
	ConnectedAt time.Time `json:"connected_at"`
	LastSeen    time.Time `json:"last_seen"`
	Remote      string    `json:"remote"`
}

type RuntimeState struct {
	ChainID      string        `json:"chain_id"`
	Running      bool          `json:"running"`
	PID          int           `json:"pid"`
	Mode         string        `json:"mode"`
	Overlay      string        `json:"overlay"`
	ListenPort   int           `json:"listen_port"`
	HopAddr      string        `json:"hop_addr"`
	LastActivity time.Time     `json:"last_activity"`
	Sessions     []SessionInfo `json:"sessions"`
}

type StatusWriter struct {
	mu       sync.Mutex
	cfg      Config
	path     string
	sessions map[*Session]*SessionInfo
}

func NewStatusWriter(cfg Config) *StatusWriter {
	path := filepath.Join(cfg.ChainDir, "runtime.json")
	return &StatusWriter{
		cfg:      cfg,
		path:     path,
		sessions: make(map[*Session]*SessionInfo),
	}
}

func (sw *StatusWriter) Register(sess *Session, remote string) *SessionInfo {
	info := &SessionInfo{
		ConnectedAt: time.Now(),
		LastSeen:    time.Now(),
		Remote:      remote,
	}
	sw.mu.Lock()
	sw.sessions[sess] = info
	sw.mu.Unlock()
	sw.flush()
	return info
}

func (sw *StatusWriter) BindClient(sess *Session, addr, deviceID string) {
	sw.mu.Lock()
	if info, ok := sw.sessions[sess]; ok {
		info.ClientAddr = addr
		info.DeviceID = deviceID
		info.LastSeen = time.Now()
	}
	sw.mu.Unlock()
	sw.flush()
}

func (sw *StatusWriter) Touch(sess *Session) {
	sw.mu.Lock()
	if info, ok := sw.sessions[sess]; ok {
		info.LastSeen = time.Now()
	}
	sw.mu.Unlock()
}

func (sw *StatusWriter) Unregister(sess *Session) {
	sw.mu.Lock()
	delete(sw.sessions, sess)
	sw.mu.Unlock()
	sw.flush()
}

func (sw *StatusWriter) StartPeriodicFlush(stop <-chan struct{}) {
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				return
			case <-ticker.C:
				sw.flush()
			}
		}
	}()
}

func (sw *StatusWriter) flush() {
	sw.mu.Lock()
	defer sw.mu.Unlock()

	var lastActivity time.Time
	list := make([]SessionInfo, 0, len(sw.sessions))
	for _, info := range sw.sessions {
		list = append(list, *info)
		if info.LastSeen.After(lastActivity) {
			lastActivity = info.LastSeen
		}
	}

	state := RuntimeState{
		ChainID:      sw.cfg.ChainID,
		Running:      true,
		PID:          os.Getpid(),
		Mode:         sw.cfg.Mode(),
		Overlay:      sw.cfg.Overlay,
		ListenPort:   sw.cfg.ListenPort,
		HopAddr:      sw.cfg.Addr,
		LastActivity: lastActivity,
		Sessions:     list,
	}
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return
	}
	tmp := sw.path + ".tmp"
	if err := os.WriteFile(tmp, append(data, '\n'), 0o644); err != nil {
		return
	}
	_ = os.Rename(tmp, sw.path)
}

type SessionRegistry struct {
	mu       sync.RWMutex
	byClient map[string]*Session
}

func NewSessionRegistry() *SessionRegistry {
	return &SessionRegistry{byClient: make(map[string]*Session)}
}

func (r *SessionRegistry) Register(clientIP net.IP, sess *Session) {
	if clientIP == nil {
		return
	}
	key := clientIP.String()
	r.mu.Lock()
	r.byClient[key] = sess
	r.mu.Unlock()
}

func (r *SessionRegistry) Unregister(clientIP net.IP) {
	if clientIP == nil {
		return
	}
	key := clientIP.String()
	r.mu.Lock()
	delete(r.byClient, key)
	r.mu.Unlock()
}

func (r *SessionRegistry) Lookup(clientIP net.IP) *Session {
	if clientIP == nil {
		return nil
	}
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.byClient[clientIP.String()]
}

func IPv4Source(packet []byte) (net.IP, error) {
	if len(packet) < 20 {
		return nil, errTruncatedPacket
	}
	if packet[0]>>4 != 4 {
		return nil, errNotIPv4
	}
	return net.IP(packet[12:16]).To4(), nil
}

var (
	errTruncatedPacket = &packetError{"packet too short"}
	errNotIPv4         = &packetError{"not ipv4"}
)

type packetError struct{ msg string }

func (e *packetError) Error() string { return e.msg }
