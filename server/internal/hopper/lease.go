package hopper

import (
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/aengix/hopper/server/internal/log"
)

type assignRequest struct {
	DeviceID string `json:"device_id"`
	ChainID  string `json:"chain_id"`
}

type assignResponse struct {
	Addr      string `json:"addr,omitempty"`
	LeaseTTL  int    `json:"lease_ttl,omitempty"`
	Error     string `json:"error,omitempty"`
}

type leaseRecord struct {
	Addr       string    `json:"addr"`
	DeviceID   string    `json:"device_id"`
	LastSeen   time.Time `json:"last_seen"`
	ConnectedAt time.Time `json:"connected_at"`
}

type LeaseManager struct {
	mu       sync.Mutex
	cfg      Config
	pool     *net.IPNet
	leases   map[string]*leaseRecord // device_id -> lease
	byAddr   map[string]string       // addr -> device_id
	leasesPath string
}

func NewLeaseManager(cfg Config) (*LeaseManager, error) {
	if cfg.ClientPool == "" {
		return nil, nil
	}
	_, pool, err := net.ParseCIDR(cfg.ClientPool)
	if err != nil {
		return nil, err
	}
	lm := &LeaseManager{
		cfg:        cfg,
		pool:       pool,
		leases:     make(map[string]*leaseRecord),
		byAddr:     make(map[string]string),
		leasesPath: filepath.Join(cfg.ChainDir, "leases.json"),
	}
	lm.load()
	go lm.sweeper()
	return lm, nil
}

func (lm *LeaseManager) load() {
	data, err := os.ReadFile(lm.leasesPath)
	if err != nil {
		return
	}
	var stored map[string]*leaseRecord
	if err := json.Unmarshal(data, &stored); err != nil {
		return
	}
	now := time.Now()
	ttl := time.Duration(lm.cfg.ClientLeaseTTLSec) * time.Second
	for deviceID, rec := range stored {
		if now.Sub(rec.LastSeen) > ttl {
			continue
		}
		lm.leases[deviceID] = rec
		lm.byAddr[rec.Addr] = deviceID
	}
}

func (lm *LeaseManager) persist() {
	lm.mu.Lock()
	defer lm.mu.Unlock()
	data, err := json.MarshalIndent(lm.leases, "", "  ")
	if err != nil {
		return
	}
	_ = os.WriteFile(lm.leasesPath, append(data, '\n'), 0o600)
}

func (lm *LeaseManager) sweeper() {
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		lm.evictExpired()
	}
}

func (lm *LeaseManager) evictExpired() {
	lm.mu.Lock()
	defer lm.mu.Unlock()
	now := time.Now()
	ttl := time.Duration(lm.cfg.ClientLeaseTTLSec) * time.Second
	for deviceID, rec := range lm.leases {
		if now.Sub(rec.LastSeen) > ttl {
			delete(lm.leases, deviceID)
			delete(lm.byAddr, rec.Addr)
			log.Infof("lease expired device=%s addr=%s", deviceID, rec.Addr)
		}
	}
	lm.persistUnlocked()
}

func (lm *LeaseManager) persistUnlocked() {
	data, err := json.MarshalIndent(lm.leases, "", "  ")
	if err != nil {
		return
	}
	_ = os.WriteFile(lm.leasesPath, append(data, '\n'), 0o600)
}

func (lm *LeaseManager) HandleAssign(payload []byte) ([]byte, error) {
	var req assignRequest
	if err := json.Unmarshal(payload, &req); err != nil {
		return lm.errorResp("invalid assign request")
	}
	if req.DeviceID == "" {
		return lm.errorResp("device_id required")
	}
	if lm.cfg.ChainID != "" && req.ChainID != "" && req.ChainID != lm.cfg.ChainID {
		return lm.errorResp("chain_id mismatch")
	}

	lm.mu.Lock()
	defer lm.mu.Unlock()

	now := time.Now()
	ttl := lm.cfg.ClientLeaseTTLSec
	if rec, ok := lm.leases[req.DeviceID]; ok {
		rec.LastSeen = now
		lm.persistUnlocked()
		return lm.okResp(rec.Addr, ttl)
	}

	addr, err := lm.allocateLocked()
	if err != nil {
		return lm.errorResp(err.Error())
	}
	rec := &leaseRecord{
		Addr:        addr,
		DeviceID:    req.DeviceID,
		LastSeen:    now,
		ConnectedAt: now,
	}
	lm.leases[req.DeviceID] = rec
	lm.byAddr[addr] = req.DeviceID
	lm.persistUnlocked()
	log.Infof("lease assigned device=%s addr=%s", req.DeviceID, addr)
	return lm.okResp(addr, ttl)
}

func (lm *LeaseManager) allocateLocked() (string, error) {
	base := lm.pool.IP.To4()
	if base == nil {
		return "", errPoolExhausted
	}
	maskOnes, _ := lm.pool.Mask.Size()
	start := int(base[3])
	if start < 2 {
		start = 2
	}
	end := start
	if maskOnes <= 24 {
		end = 254
	}
	for host := start; host <= end; host++ {
		ip := net.IPv4(base[0], base[1], base[2], byte(host))
		if !lm.pool.Contains(ip) || host < 2 {
			continue
		}
		addr := ip.String()
		if _, used := lm.byAddr[addr]; !used {
			return addr, nil
		}
	}
	return "", errPoolExhausted
}

func (lm *LeaseManager) Touch(addr string) {
	lm.mu.Lock()
	defer lm.mu.Unlock()
	deviceID, ok := lm.byAddr[addr]
	if !ok {
		return
	}
	if rec, ok := lm.leases[deviceID]; ok {
		rec.LastSeen = time.Now()
	}
}

func (lm *LeaseManager) okResp(addr string, ttl int) ([]byte, error) {
	return json.Marshal(assignResponse{Addr: addr, LeaseTTL: ttl})
}

func (lm *LeaseManager) errorResp(msg string) ([]byte, error) {
	return json.Marshal(assignResponse{Error: msg})
}

var errPoolExhausted = &poolError{"client pool exhausted"}

type poolError struct{ msg string }

func (e *poolError) Error() string { return e.msg }
