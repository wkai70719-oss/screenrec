//go:build darwin && cgo

package main

/*
#cgo CFLAGS: -x objective-c -fobjc-arc -mmacosx-version-min=10.15
#cgo LDFLAGS: -framework Foundation -framework AVFoundation -framework CoreMedia -framework CoreGraphics -framework CoreVideo -mmacosx-version-min=10.15
#include <stdlib.h>
#include "recorder.h"
*/
import "C"

import (
 "fmt"
 "os"
 "os/signal"
 "path/filepath"
 "syscall"
 "time"
 "unsafe"
)

func main() {
 if err := run(); err != nil { fmt.Fprintln(os.Stderr, "screenrec:", err); os.Exit(1) }
}
func run() error {
 dir, err := filepath.Abs(".MP4"); if err != nil { return err }
 if err = os.MkdirAll(dir, 0755); err != nil { return fmt.Errorf("create .MP4 directory: %w", err) }
 // Reserve a unique name, avoiding overwrite even when recordings start in the same second.
 var f *os.File
 for i := 0; i < 1000; i++ {
  name := time.Now().Format("2006-01-02_15-04-05")
  if i > 0 { name += fmt.Sprintf("_%03d", i) }
  f, err = os.OpenFile(filepath.Join(dir, name+".mp4"), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
  if os.IsExist(err) { continue }; break
 }
 if err != nil { return fmt.Errorf("reserve output file: %w", err) }
 path := f.Name(); if err = f.Close(); err != nil { return err }; if err = os.Remove(path); err != nil { return err }
 cpath := C.CString(path); defer C.free(unsafe.Pointer(cpath))
 sig := make(chan os.Signal, 1); signal.Notify(sig, os.Interrupt, syscall.SIGTERM); defer signal.Stop(sig)
 fmt.Println("Requesting screen recording access; follow the macOS permission prompt if shown.")
 if C.rec_start(cpath) == 0 { return fmt.Errorf("%s", C.GoString(C.rec_error())) }
 fmt.Printf("● RECORDING — %s\nPress Ctrl+C to stop and finalize the video.\n", path)
 ticker := time.NewTicker(250*time.Millisecond); defer ticker.Stop()
 deadline := time.Now().Add(10*time.Second)
 for {
  select {
  case <-sig:
   fmt.Println("Stopping and finalizing…")
   if C.rec_stop() == 0 { return fmt.Errorf("%s", C.GoString(C.rec_error())) }
   fmt.Println("Saved:", path); return nil
  case <-ticker.C:
   if C.rec_failed() != 0 { C.rec_stop(); return fmt.Errorf("%s", C.GoString(C.rec_error())) }
   if time.Now().After(deadline) && C.rec_has_frame() == 0 { C.rec_stop(); return fmt.Errorf("no first frame within 10 seconds; check screen recording permission") }
  }
 }
}


