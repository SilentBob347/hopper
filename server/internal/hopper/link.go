package hopper

import (
	"net"
	"sync"
	"time"

	"github.com/aengix/hopper/server/internal/iptunnel"
	"github.com/aengix/hopper/server/internal/log"
)

type frameConn struct {
	net.Conn
	mu sync.Mutex
}

func (c *frameConn) writeFrame(frame iptunnel.Frame) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	return iptunnel.WriteFrame(c.Conn, frame)
}

func pumpFrames(conn net.Conn, onData func([]byte) error) error {
	for {
		frame, err := iptunnel.ReadFrame(conn)
		if err != nil {
			return err
		}
		switch frame.Type {
		case iptunnel.TypeKeepalive:
			log.Debugf("keepalive from %s", conn.RemoteAddr())
		case iptunnel.TypeData:
			if err := onData(frame.Payload); err != nil {
				return err
			}
		}
	}
}

func keepaliveLoop(conn *frameConn, stop <-chan struct{}) {
	ticker := time.NewTicker(iptunnel.KeepaliveSecs * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			if err := conn.writeFrame(iptunnel.Frame{Type: iptunnel.TypeKeepalive}); err != nil {
				return
			}
		}
	}
}

func writeData(conn *frameConn, packet []byte) error {
	return conn.writeFrame(iptunnel.Frame{
		Type:    iptunnel.TypeData,
		Payload: append([]byte(nil), packet...),
	})
}
