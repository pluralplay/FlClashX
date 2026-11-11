//go:build linux

package platform

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"encoding/hex"
	"net"
	"os"
	"strconv"
	"strings"
)

var netIndexOfLocal = -1
var netIndexOfUid = -1

var procNetDir = "/proc/net/"

func QuerySocketUidFromProcFs(source, target net.Addr) int {
	if netIndexOfLocal < 0 || netIndexOfUid < 0 {
		return -1
	}

	network := source.Network()

	if strings.HasSuffix(network, "4") || strings.HasSuffix(network, "6") {
		network = network[:len(network)-1]
	}

	path := procNetDir + network
	// A socket that has not connected lists the address it was bound to,
	// usually the wildcard, while its packets carry the interface's own.
	wildcard := network == "udp"

	var sIP net.IP
	var sPort int

	switch s := source.(type) {
	case *net.TCPAddr:
		sIP = s.IP
		sPort = s.Port
	case *net.UDPAddr:
		sIP = s.IP
		sPort = s.Port
	default:
		return -1
	}

	sIP = sIP.To16()
	if sIP == nil {
		return -1
	}

	// An IPv4-mapped socket in the v6 table shares its port space with the v4
	// one, so both tables are read before either settles the owner.
	found := doQuery(path+"6", sIP, sPort, addressColumnOf(target, net.IP.To16), wildcard)
	if sIP = sIP.To4(); sIP != nil {
		found = found.join(doQuery(path, sIP, sPort, addressColumnOf(target, net.IP.To4), wildcard))
	}
	if owner := soleOwner(found.connected); owner != -1 {
		return owner
	}
	if len(found.exact) > 0 {
		return soleOwner(found.exact)
	}
	return soleOwner(found.bound)
}

// The owners of the rows a lookup found: bound to the source itself, also
// connected to the target, or bound to the unspecified address on its port.
type socketOwners struct {
	exact, connected, bound []int
}

func (o socketOwners) join(other socketOwners) socketOwners {
	return socketOwners{
		exact:     append(o.exact, other.exact...),
		connected: append(o.connected, other.connected...),
		bound:     append(o.bound, other.bound...),
	}
}

func addressColumnOf(addr net.Addr, family func(net.IP) net.IP) []byte {
	var ip net.IP
	var port int
	switch a := addr.(type) {
	case *net.TCPAddr:
		ip, port = a.IP, a.Port
	case *net.UDPAddr:
		ip, port = a.IP, a.Port
	default:
		return nil
	}
	if ip = family(ip); ip == nil {
		return nil
	}
	return addressColumn(ip, port)
}

func soleOwner(uids []int) int {
	if len(uids) == 0 {
		return -1
	}
	for _, uid := range uids[1:] {
		if uid != uids[0] {
			return -1
		}
	}
	return uids[0]
}

func addressColumn(sIP net.IP, sPort int) []byte {
	ip := nativeEndianIP(sIP)
	column := make([]byte, 0, hex.EncodedLen(len(ip))+1+4)

	encoded := make([]byte, hex.EncodedLen(len(ip)))
	hex.Encode(encoded, ip)
	column = append(column, encoded...)

	column = append(column, ':')

	var port [2]byte
	binary.BigEndian.PutUint16(port[:], uint16(sPort))
	var encodedPort [4]byte
	hex.Encode(encodedPort[:], port[:])
	return append(column, encodedPort[:]...)
}

func column(row []byte, index int) []byte {
	for i := 0; ; i++ {
		row = bytes.TrimLeft(row, " \t")
		if len(row) == 0 {
			return nil
		}
		end := bytes.IndexAny(row, " \t")
		if end < 0 {
			end = len(row)
		}
		if i == index {
			return row[:end]
		}
		row = row[end:]
	}
}

// Several sockets can list one local address: SO_REUSEADDR lets apps bind the
// same UDP address, and a TIME_WAIT row outlives the connection that held its
// port. The remote address tells them apart when it can; otherwise apps that
// disagree leave the socket without an owner.
func doQuery(path string, sIP net.IP, sPort int, remote []byte, wildcard bool) (found socketOwners) {
	file, err := os.Open(path)
	if err != nil {
		return found
	}

	defer func(file *os.File) {
		_ = file.Close()
	}(file)

	local := addressColumn(sIP, sPort)
	unspecified := addressColumn(make(net.IP, len(sIP)), sPort)

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		row := scanner.Bytes()
		address := column(row, netIndexOfLocal)

		if bytes.EqualFold(local, address) {
			owner := uidOf(row)
			found.exact = append(found.exact, owner)
			if remote != nil && bytes.EqualFold(remote, column(row, netIndexOfLocal+1)) {
				found.connected = append(found.connected, owner)
			}
			continue
		}
		if wildcard && bytes.EqualFold(unspecified, address) {
			found.bound = append(found.bound, uidOf(row))
		}
	}
	return found
}

func uidOf(row []byte) int {
	uidColumn := column(row, netIndexOfUid)
	if uidColumn == nil {
		return -1
	}

	uid, err := strconv.Atoi(string(uidColumn))
	if err != nil {
		return -1
	}

	return uid
}

func nativeEndianIP(ip net.IP) []byte {
	result := make([]byte, len(ip))

	for i := 0; i < len(ip); i += 4 {
		value := binary.BigEndian.Uint32(ip[i:])

		binary.NativeEndian.PutUint32(result[i:], value)
	}

	return result
}

func init() {
	file, err := os.Open("/proc/net/tcp")
	if err != nil {
		return
	}

	defer func(file *os.File) {
		_ = file.Close()
	}(file)

	reader := bufio.NewReader(file)

	header, _, err := reader.ReadLine()
	if err != nil {
		return
	}

	columns := strings.Fields(string(header))

	var txQueue, rxQueue, tr, tmWhen bool

	for idx, col := range columns {
		offset := 0

		if txQueue && rxQueue {
			offset--
		}

		if tr && tmWhen {
			offset--
		}

		switch col {
		case "tx_queue":
			txQueue = true
		case "rx_queue":
			rxQueue = true
		case "tr":
			tr = true
		case "tm->when":
			tmWhen = true
		case "local_address":
			netIndexOfLocal = idx + offset
		case "uid":
			netIndexOfUid = idx + offset
		}
	}
}
