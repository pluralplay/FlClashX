package core

import (
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func handleGetTraffic(onlyStatisticsProxy bool) Traffic {
	if onlyStatisticsProxy {
		up, down := proxiedTrafficNow()
		return Traffic{Up: up, Down: down}
	}
	up, down := statistic.DefaultManager.Now()
	return Traffic{Up: up, Down: down}
}

func handleGetTotalTraffic(onlyStatisticsProxy bool) Traffic {
	if onlyStatisticsProxy {
		return Traffic{Up: proxiedTraffic.up.Load(), Down: proxiedTraffic.down.Load()}
	}
	up, down := statistic.DefaultManager.Total()
	return Traffic{Up: up, Down: down}
}

func handleResetTraffic() {
	statistic.DefaultManager.ResetStatistic()
	resetProxiedTraffic()
}

func handleGetConnections() *statistic.Snapshot {
	return statistic.DefaultManager.Snapshot()
}

func handleGetConnectionCount() int {
	count := 0
	statistic.DefaultManager.Range(func(statistic.Tracker) bool {
		count++
		return true
	})
	return count
}

func handleCloseConnections() bool {
	statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
		_ = c.Close()
		return true
	})
	return true
}

func handleResetConnections() bool {
	resolver.ResetConnection()
	return true
}

// A connection that went out over a network the device has left hangs until
// TCP gives up on it, and so do the DNS clients' pooled connections.
func handleResetNetwork() {
	handleCloseConnections()
	resolver.ResetConnection()
}

func handleCloseConnection(connectionId string) bool {
	c := statistic.DefaultManager.Get(connectionId)
	if c == nil {
		return false
	}
	_ = c.Close()
	return true
}
