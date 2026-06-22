package hopper

import (
	"fmt"
	"net"
	"os"
	"time"

	"golang.org/x/crypto/ssh"

	"github.com/aengix/hopper/server/internal/log"
)

func dialNextHop(next NextHop) (net.Conn, error) {
	keyBytes, err := os.ReadFile(next.KeyPath)
	if err != nil {
		return nil, fmt.Errorf("read key %s: %w", next.KeyPath, err)
	}

	signer, err := ssh.ParsePrivateKey(keyBytes)
	if err != nil {
		return nil, fmt.Errorf("parse key: %w", err)
	}

	addr := fmt.Sprintf("%s:%d", next.Host, next.Port)
	log.Infof("ssh connect %s@%s", next.User, addr)

	client, err := ssh.Dial("tcp", addr, &ssh.ClientConfig{
		User:            next.User,
		Auth:            []ssh.AuthMethod{ssh.PublicKeys(signer)},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         15 * time.Second,
	})
	if err != nil {
		return nil, fmt.Errorf("ssh dial %s: %w", addr, err)
	}

	tunnelPort := next.TunnelPort
	if tunnelPort == 0 {
		tunnelPort = DefaultListenPort
	}
	target := fmt.Sprintf("%s:%d", DefaultListenHost, tunnelPort)
	log.Infof("ssh forward -> %s", target)

	channel, reqs, err := client.Conn.OpenChannel("direct-tcpip", ssh.Marshal(struct {
		Raddr string
		Rport uint32
		Laddr string
		Lport uint32
	}{
		Raddr: DefaultListenHost,
		Rport: uint32(tunnelPort),
		Laddr: "127.0.0.1",
		Lport: 0,
	}))
	if err != nil {
		_ = client.Close()
		return nil, fmt.Errorf("open direct-tcpip %s: %w", target, err)
	}
	go ssh.DiscardRequests(reqs)

	return &sshConn{Channel: channel, client: client}, nil
}

type sshConn struct {
	ssh.Channel
	client *ssh.Client
}

func (c *sshConn) LocalAddr() net.Addr  { return &net.TCPAddr{IP: net.IPv4zero, Port: 0} }
func (c *sshConn) RemoteAddr() net.Addr { return &net.TCPAddr{IP: net.IPv4zero, Port: 0} }

func (c *sshConn) SetDeadline(t time.Time) error      { return nil }
func (c *sshConn) SetReadDeadline(t time.Time) error  { return nil }
func (c *sshConn) SetWriteDeadline(t time.Time) error { return nil }

func (c *sshConn) Close() error {
	_ = c.Channel.Close()
	return c.client.Close()
}
