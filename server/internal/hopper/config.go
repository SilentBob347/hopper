package hopper

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const (
	DefaultListenHost = "127.0.0.1"
	DefaultListenPort = 7400
	DefaultOverlay    = "10.64.0.0/24"
	DefaultTUN        = "hopper0"
	DefaultClientAddr = "10.64.0.2"
	DefaultKeyPath    = "~/.hopper/id_ed25519"
)

const (
	ViaIngress = "ingress"
	ViaNext    = "next"
	ViaTun     = "tun"
)

type NextHop struct {
	Host    string `json:"host"`
	Port    int    `json:"port"`
	User    string `json:"user"`
	KeyPath string `json:"key_path"`
}

type Route struct {
	Dest string `json:"dest"`
	Via  string `json:"via"`
}

type Config struct {
	Addr       string   `json:"addr"`
	ClientAddr string   `json:"client_addr"`
	Overlay    string   `json:"overlay"`
	TUN        string   `json:"tun"`
	ListenHost string   `json:"listen_host"`
	ListenPort int      `json:"listen_port"`
	Next       *NextHop `json:"next"`
	Routes     []Route  `json:"routes"`
	NAT        bool     `json:"nat"`
}

func LoadConfig(path string) (Config, error) {
	cfg := Config{
		ClientAddr: DefaultClientAddr,
		Overlay:    DefaultOverlay,
		TUN:        DefaultTUN,
		ListenHost: DefaultListenHost,
		ListenPort: DefaultListenPort,
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
	if c.Next != nil {
		if c.Next.Port == 0 {
			c.Next.Port = 22
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

func (c Config) EffectiveRoutes() []Route {
	if len(c.Routes) > 0 {
		return c.Routes
	}

	routes := []Route{{Dest: c.Overlay, Via: ViaTun}}
	if c.ClientAddr != "" {
		routes = append(routes, Route{Dest: c.ClientAddr + "/32", Via: ViaIngress})
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
