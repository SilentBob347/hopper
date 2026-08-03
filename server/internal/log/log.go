package log

import (
	"io"
	"log"
	"os"
)

var Verbose bool

func init() {
	log.SetOutput(os.Stderr)
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds)
}

func logSetOutput(w io.Writer) { log.SetOutput(w) }

func SetVerbose(v bool) { Verbose = v }

func Infof(format string, args ...any)  { log.Printf("INFO "+format, args...) }
func Warnf(format string, args ...any)  { log.Printf("WARN "+format, args...) }
func Errorf(format string, args ...any) { log.Printf("ERROR "+format, args...) }

func Debugf(format string, args ...any) {
	if Verbose {
		log.Printf("DEBUG "+format, args...)
	}
}
