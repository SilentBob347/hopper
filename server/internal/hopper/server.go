package hopper

import (
	"fmt"
	"io"
	"net"
	"sync"
	"sync/atomic"

	"github.com/aengix/hopper/server/internal/iptunnel"
	"github.com/aengix/hopper/server/internal/log"
)

type Server struct {
	cfg      Config
	sessions atomic.Int32
	tun      io.ReadWriteCloser
	active   atomic.Pointer[Session]
	tunOnce  sync.Once
}

func NewServer(cfg Config) *Server {
	return &Server{cfg: cfg}
}

func (s *Server) Prepare() error {
	if s.cfg.Addr == "" {
		log.Infof("no overlay addr configured — pure forwarder")
		return nil
	}

	tun, err := iptunnel.OpenTUN(s.cfg.TUN)
	if err != nil {
		return fmt.Errorf("open tun %s: %w", s.cfg.TUN, err)
	}
	if err := iptunnel.ConfigureTUN(s.cfg.TUN, s.cfg.Addr, s.cfg.Overlay); err != nil {
		_ = tun.Close()
		return fmt.Errorf("configure tun: %w", err)
	}
	s.tun = tun
	s.startTUNReader()
	if s.cfg.NAT {
		if err := setupNAT(s.cfg.Overlay, s.cfg.TUN); err != nil {
			log.Warnf("NAT setup: %v", err)
		}
	}
	log.Infof("overlay %s on %s (%s)", s.cfg.Addr, s.cfg.TUN, s.cfg.Overlay)
	return nil
}

func (s *Server) startTUNReader() {
	if s.tun == nil {
		return
	}
	s.tunOnce.Do(func() {
		go func() {
			buf := make([]byte, 1500)
			for {
				n, err := s.tun.Read(buf)
				if err != nil {
					log.Warnf("tun read ended: %v", err)
					return
				}
				packet := append([]byte(nil), buf[:n]...)
				sess := s.active.Load()
				if sess == nil {
					log.Debugf("tun packet dropped (no active session)")
					continue
				}
				if err := sess.routePacket(packet, ViaTun); err != nil {
					log.Warnf("tun route: %v", err)
				}
			}
		}()
	})
}

func (s *Server) Close() {
	if s.tun != nil {
		_ = s.tun.Close()
	}
}

func (s *Server) Listen() (net.Listener, int, error) {
	addr := fmt.Sprintf("%s:%d", s.cfg.ListenHost, s.cfg.ListenPort)
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return nil, 0, err
	}
	port := ln.Addr().(*net.TCPAddr).Port
	log.Infof("hopperd bound %s mode=%s overlay=%s", addr, s.cfg.Mode(), s.cfg.Overlay)
	return ln, port, nil
}

func (s *Server) ServeConn(conn net.Conn) {
	s.sessions.Add(1)
	defer func() {
		s.sessions.Add(-1)
		_ = conn.Close()
	}()

	sess, err := NewSession(s, conn)
	if err != nil {
		log.Errorf("session setup from %s: %v", conn.RemoteAddr(), err)
		return
	}
	_ = sess.Run()
}
