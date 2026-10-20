package fdbased

import (
	"github.com/metacubex/gvisor/pkg/tcpip"

	"golang.org/x/sys/unix"
)

func TranslateErrno(e unix.Errno) tcpip.Error {
	switch e {
	case unix.EEXIST:
		return &tcpip.ErrDuplicateAddress{}
	case unix.ENETUNREACH:
		return &tcpip.ErrHostUnreachable{}
	case unix.EINVAL:
		return &tcpip.ErrInvalidEndpointState{}
	case unix.EALREADY:
		return &tcpip.ErrAlreadyConnecting{}
	case unix.EISCONN:
		return &tcpip.ErrAlreadyConnected{}
	case unix.EADDRINUSE:
		return &tcpip.ErrPortInUse{}
	case unix.EADDRNOTAVAIL:
		return &tcpip.ErrBadLocalAddress{}
	case unix.EPIPE:
		return &tcpip.ErrClosedForSend{}
	case unix.EWOULDBLOCK:
		return &tcpip.ErrWouldBlock{}
	case unix.ECONNREFUSED:
		return &tcpip.ErrConnectionRefused{}
	case unix.ETIMEDOUT:
		return &tcpip.ErrTimeout{}
	case unix.EINPROGRESS:
		return &tcpip.ErrConnectStarted{}
	case unix.EDESTADDRREQ:
		return &tcpip.ErrDestinationRequired{}
	case unix.ENOTSUP:
		return &tcpip.ErrNotSupported{}
	case unix.ENOTTY:
		return &tcpip.ErrQueueSizeNotSupported{}
	case unix.ENOTCONN:
		return &tcpip.ErrNotConnected{}
	case unix.ECONNRESET:
		return &tcpip.ErrConnectionReset{}
	case unix.ECONNABORTED:
		return &tcpip.ErrConnectionAborted{}
	case unix.EMSGSIZE:
		return &tcpip.ErrMessageTooLong{}
	case unix.ENOBUFS:
		return &tcpip.ErrNoBufferSpace{}
	default:
		return &tcpip.ErrInvalidEndpointState{}
	}
}
