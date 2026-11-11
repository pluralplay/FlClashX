package stopfd

import (
	"fmt"

	"golang.org/x/sys/unix"
)

type StopFD struct {
	ReadFD  int
	WriteFD int
}

func New() (StopFD, error) {
	fds := make([]int, 2)
	err := unix.Pipe(fds)
	if err != nil {
		return StopFD{ReadFD: -1, WriteFD: -1}, fmt.Errorf("failed to create pipe: %w", err)
	}

	if err := unix.SetNonblock(fds[0], true); err != nil {
		unix.Close(fds[0])
		unix.Close(fds[1])
		return StopFD{ReadFD: -1, WriteFD: -1}, fmt.Errorf("failed to set read end non-blocking: %w", err)
	}

	if err := unix.SetNonblock(fds[1], true); err != nil {
		unix.Close(fds[0])
		unix.Close(fds[1])
		return StopFD{ReadFD: -1, WriteFD: -1}, fmt.Errorf("failed to set write end non-blocking: %w", err)
	}

	return StopFD{ReadFD: fds[0], WriteFD: fds[1]}, nil
}

func (sf *StopFD) Stop() {
	signal := []byte{1}
	if n, err := unix.Write(sf.WriteFD, signal); n != len(signal) || err != nil {
		panic(fmt.Sprintf("write(WriteFD) = (%d, %s), want (%d, nil)", n, err, len(signal)))
	}
}

func (sf *StopFD) Close() error {
	var err1, err2 error
	if sf.ReadFD != -1 {
		err1 = unix.Close(sf.ReadFD)
		sf.ReadFD = -1
	}
	if sf.WriteFD != -1 {
		err2 = unix.Close(sf.WriteFD)
		sf.WriteFD = -1
	}
	if err1 != nil {
		return err1
	}
	return err2
}

func (sf *StopFD) EFD() int {
	return sf.ReadFD
}
