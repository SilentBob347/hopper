package hopper

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const (
	DefaultListenHost       = "127.0.0.1"
	DefaultListenPort       = 7400
	DefaultOverlay          = "10.64.0.0/24"
	DefaultTUN              = "hopper0"
	DefaultKeyPath          = "~/.hopper/id_ed25519"
	DefaultClientLeaseTTL   = 3600
	DefaultClientPoolSuffix = ".2/24"
)

const (
	ViaIngress = "ingress"
	ViaNext    = "next"
	ViaTun     = "tun"
)

type NextHop struct {
	Host        string `json:"host"`
	Port        int    `json:"port"`
	User        string `json:"user"`
	KeyPath     string `json:"key_path"`
	TunnelPort  int    `json:"tunnel_port"`
}

type Route struct {
	Dest string `json:"dest"`
	Via  string `json:"via"`
}

type Config struct {
	ChainID            string   `json:"chain_id"`
	Addr               string   `json:"addr"`
	ClientPool         string   `json:"client_pool"`
	ClientLeaseTTLSec  int      `json:"client_lease_ttl_sec"`
	Overlay            string   `json:"overlay"`
	TUN                string   `json:"tun"`
	ListenHost         string   `json:"listen_host"`
	ListenPort         int      `json:"listen_port"`
	Next               *NextHop `json:"next"`
	Routes             []Route  `json:"routes"`
	NAT                bool     `json:"nat"`
	ChainDir           string   `json:"-"`
}

func LoadConfig(path string) (Config, error) {
	cfg := Config{
		Overlay:           DefaultOverlay,
		TUN:               DefaultTUN,
		ListenHost:        DefaultListenHost,
		ListenPort:        DefaultListenPort,
		ClientLeaseTTLSec: DefaultClientLeaseTTL,
	}

	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return cfg.withDefaults(), nil
		}
		return cfg, err
	}

	if err := json.Unmarshal(data, &cfg); err != nil {
		return cfg, fmt.Errorf("parse %s: %w", path, err)
	}

	cfg.ChainDir = filepath.Dir(path)
	return cfg.withDefaults(), nil
}

func (c Config) withDefaults() Config {
	if c.Overlay == "" {
		c.Overlay = DefaultOverlay
	}
	if c.TUN == "" {
		c.TUN = DefaultTUN
	}
	if c.ListenHost == "" {
		c.ListenHost = DefaultListenHost
	}
	if c.ListenPort == 0 {
		c.ListenPort = DefaultListenPort
	}
	if c.ClientLeaseTTLSec <= 0 {
		c.ClientLeaseTTLSec = DefaultClientLeaseTTL
	}
	if c.Next != nil {
		if c.Next.Port == 0 {
			c.Next.Port = 22
		}
		if c.Next.TunnelPort == 0 {
			c.Next.TunnelPort = DefaultListenPort
		}
		if c.Next.KeyPath == "" {
			c.Next.KeyPath = DefaultKeyPath
		}
		c.Next.KeyPath = expandHome(c.Next.KeyPath)
	}
	if !c.HasNext() && !c.NAT {
		c.NAT = true
	}
	return c
}

func (c Config) HasNext() bool {
	return c.Next != nil && strings.TrimSpace(c.Next.Host) != ""
}

func (c Config) Mode() string {
	if c.HasNext() {
		return "relay"
	}
	return "exit"
}

func (c Config) IsEntry() bool {
	return c.ClientPool != ""
}

func (c Config) EffectiveRoutes() []Route {
	if len(c.Routes) > 0 {
		return c.Routes
	}

	routes := []Route{{Dest: c.Overlay, Via: ViaTun}}
	if c.ClientPool != "" {
		routes = append(routes, Route{Dest: c.ClientPool, Via: ViaIngress})
	}
	if c.Addr != "" {
		routes = append(routes, Route{Dest: c.Addr + "/32", Via: ViaTun})
	}
	if c.HasNext() {
		routes = append(routes, Route{Dest: "0.0.0.0/0", Via: ViaNext})
	} else {
		routes = append(routes, Route{Dest: "0.0.0.0/0", Via: ViaTun})
	}
	return routes
}

func expandHome(path string) string {
	if strings.HasPrefix(path, "~/") {
		home, err := os.UserHomeDir()
		if err != nil {
			return path
		}
		return filepath.Join(home, path[2:])
	}
	return path
}
