//go:build linux

package iptunnel

import (
	"fmt"
	"os"
	"os/exec"
	"syscall"
	"unsafe"
)

const (
	iffTUN   = 0x0001
	iffNoPI  = 0x1000
	tunSetIFF = 0x400454ca
)

type ifreq struct {
	Name  [16]byte
	Flags uint16
	_     [22]byte
}

// OpenTUN creates a layer-3 TUN device (no PI header — raw IP packets).
func OpenTUN(name string) (*os.File, error) {
	fd, err := syscall.Open("/dev/net/tun", syscall.O_RDWR, 0)
	if err != nil {
		return nil, fmt.Errorf("open /dev/net/tun: %w", err)
	}

	var req ifreq
	copy(req.Name[:], name)
	req.Flags = iffTUN | iffNoPI

	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), tunSetIFF, uintptr(unsafe.Pointer(&req)))
	if errno != 0 {
		_ = syscall.Close(fd)
		return nil, fmt.Errorf("ioctl TUNSETIFF: %v", errno)
	}

	file := os.NewFile(uintptr(fd), "/dev/net/tun")
	if file == nil {
		_ = syscall.Close(fd)
		return nil, fmt.Errorf("os.NewFile failed")
	}
	return file, nil
}

// ConfigureTUN brings the device up, assigns the node overlay /32, and adds the overlay route.
func ConfigureTUN(name, addr, overlay string) error {
	cmd := exec.Command("ip", "link", "set", name, "up")
	_ = cmd.Run()

	cmd = exec.Command("ip", "addr", "replace", addr+"/32", "dev", name)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("ip addr: %w", err)
	}

	if overlay != "" {
		cmd = exec.Command("ip", "route", "replace", overlay, "dev", name)
		_ = cmd.Run()
	}
	return nil
}
