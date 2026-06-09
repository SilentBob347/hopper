package hopper

import (
	"net"
	"sync"

	"github.com/aengix/hopper/server/internal/log"
)

type Session struct {
	srv        *Server
	cfg        Config
	routes     *RouteTable
	ingress    *frameConn
	downstream *frameConn
}

func NewSession(srv *Server, ingress net.Conn) (*Session, error) {
	routes, err := NewRouteTable(srv.cfg.EffectiveRoutes())
	if err != nil {
		return nil, err
	}

	s := &Session{
		srv:     srv,
		cfg:     srv.cfg,
		routes:  routes,
		ingress: &frameConn{Conn: ingress},
	}

	if srv.cfg.HasNext() {
		down, err := dialNextHop(*srv.cfg.Next, srv.cfg.ListenPort)
		if err != nil {
			return nil, err
		}
		s.downstream = &frameConn{Conn: down}
	}

	return s, nil
}

func (s *Session) Run() error {
	log.Infof("session start mode=%s remote=%s", s.cfg.Mode(), s.ingress.RemoteAddr())

	s.srv.active.Store(s)
	defer s.srv.active.Store(nil)

	stop := make(chan struct{})
	defer close(stop)

	var wg sync.WaitGroup
	errCh := make(chan error, 2)

	startPump := func(name string, conn *frameConn, from string) {
		if conn == nil {
			return
		}
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := pumpFrames(conn.Conn, func(packet []byte) error {
				return s.routePacket(packet, from)
			}); err != nil {
				log.Infof("%s pump ended: %v", name, err)
				errCh <- err
			}
		}()
	}

	go keepaliveLoop(s.ingress, stop)
	if s.downstream != nil {
		go keepaliveLoop(s.downstream, stop)
	}

	startPump("ingress", s.ingress, ViaIngress)
	startPump("downstream", s.downstream, ViaNext)

	var err error
	select {
	case err = <-errCh:
	}

	close(stop)
	wg.Wait()
	log.Infof("session end: %v", err)
	return err
}

func (s *Session) routePacket(packet []byte, from string) error {
	dest, err := IPv4Dest(packet)
	if err != nil {
		log.Debugf("skip non-ipv4 packet from %s: %v", from, err)
		return nil
	}

	if s.cfg.ClientAddr != "" && from == ViaNext && dest.String() == s.cfg.ClientAddr {
		return writeData(s.ingress, packet)
	}

	via := s.routes.Lookup(dest)
	if from == via {
		switch from {
		case ViaIngress:
			if s.downstream != nil {
				via = ViaNext
			} else if s.srv.tun != nil {
				via = ViaTun
			}
		case ViaNext:
			via = ViaIngress
		case ViaTun:
			via = ViaIngress
		}
	}

	log.Debugf("route %s -> %s via %s", from, dest, via)

	switch via {
	case ViaIngress:
		return writeData(s.ingress, packet)
	case ViaNext:
		if s.downstream == nil {
			if s.srv.tun != nil {
				_, err := s.srv.tun.Write(packet)
				return err
			}
			return writeData(s.ingress, packet)
		}
		return writeData(s.downstream, packet)
	case ViaTun:
		if s.srv.tun == nil {
			if s.downstream != nil {
				return writeData(s.downstream, packet)
			}
			return writeData(s.ingress, packet)
		}
		_, err := s.srv.tun.Write(packet)
		return err
	default:
		return nil
	}
}
