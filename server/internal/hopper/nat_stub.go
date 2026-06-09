//go:build !linux

package hopper

func setupNAT(_, _ string) error {
	return nil
}
