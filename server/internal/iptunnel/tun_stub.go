//go:build !linux

package iptunnel

import (
	"fmt"
	"os"
)

func OpenTUN(name string) (*os.File, error) {
	return nil, fmt.Errorf("TUN is only supported on linux")
}

func ConfigureTUN(name, addr, overlay string) error {
	return fmt.Errorf("TUN is only supported on linux")
}
