package core

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

type gatedAdapter struct {
	constant.ProxyAdapter
	gate func(ctx context.Context) error
}

func (a gatedAdapter) DialContext(ctx context.Context, metadata *constant.Metadata) (constant.Conn, error) {
	if err := a.gate(ctx); err != nil {
		return nil, err
	}
	return a.ProxyAdapter.DialContext(ctx, metadata)
}

func gatedProxy(name string, gate func(ctx context.Context) error) constant.Proxy {
	return adapter.NewProxy(gatedAdapter{outbound.NewDirectWithOption(outbound.DirectOption{Name: name}), gate})
}

func lagging(lag time.Duration) func(ctx context.Context) error {
	return func(ctx context.Context) error {
		select {
		case <-time.After(lag):
			return nil
		case <-ctx.Done():
			return ctx.Err()
		}
	}
}

func laggingProxy(name string, lag time.Duration) constant.Proxy {
	return gatedProxy(name, lagging(lag))
}

func testBalancer(t *testing.T, members ...constant.Proxy) {
	t.Helper()
	tunnel.UpdateProxies(map[string]constant.Proxy{"Balance": balanceOver(t, "Balance", members...)}, nil)
	t.Cleanup(func() {
		tunnel.UpdateProxies(nil, nil)
		// Probes still running once the balancer answered hold slots the next test counts.
		for deadline := time.Now().Add(5 * time.Second); len(delayTestSlots) > 0; time.Sleep(10 * time.Millisecond) {
			if time.Now().After(deadline) {
				t.Fatal("member probes still hold delay test slots")
			}
		}
	})
}

func TestABalancerAnswersWhileTheMemberItWouldPickIsDown(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(noContentAfterAMillisecond))
	defer server.Close()
	testBalancer(t, laggingProxy("down", time.Hour), namedProxy("up"))

	start := time.Now()
	delay := handleTestDelay(&TestDelayParams{ProxyName: "Balance", TestUrl: server.URL, Timeout: 2000})

	if delay == nil || delay.Value <= 0 {
		t.Fatalf("delay = %+v, want the live member's", delay)
	}
	if elapsed := time.Since(start); elapsed > time.Second {
		t.Errorf("answered after %v, want it not waiting out the member that is down", elapsed)
	}
}

func TestABalancerAnswerLeavesItsSlowerMembersAlive(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(noContentAfterAMillisecond))
	defer server.Close()
	dialing := make(chan struct{})
	slow := gatedProxy("slow", func(ctx context.Context) error {
		close(dialing)
		return lagging(200 * time.Millisecond)(ctx)
	})
	fast := gatedProxy("fast", func(context.Context) error {
		<-dialing
		return nil
	})
	testBalancer(t, fast, slow)

	if delay := handleTestDelay(&TestDelayParams{ProxyName: "Balance", TestUrl: server.URL, Timeout: 3000}); delay == nil || delay.Value <= 0 {
		t.Fatalf("delay = %+v, want the fast member's", delay)
	}

	for wait := time.Now().Add(2 * time.Second); len(slow.DelayHistory()) == 0; {
		if time.Now().After(wait) {
			t.Fatal("the slower member never finished its test")
		}
		time.Sleep(10 * time.Millisecond)
	}
	if !slow.AliveForTestUrl(server.URL) {
		t.Error("the slower member was recorded as dead once the balancer had its answer")
	}
}

func TestABalancerWithEveryMemberDownTimesOut(t *testing.T) {
	testBalancer(t, laggingProxy("a", time.Hour), laggingProxy("b", time.Hour))

	delay := handleTestDelay(&TestDelayParams{ProxyName: "Balance", TestUrl: "http://127.0.0.1:1", Timeout: 200})

	if delay == nil || delay.Value != delayTimedOut {
		t.Errorf("delay = %+v, want value %d", delay, delayTimedOut)
	}
}

func TestABalancerBehindASelectorAnswersWhileOneOfItsMembersIsDown(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(noContentAfterAMillisecond))
	defer server.Close()
	inner := balanceOver(t, "Inner", laggingProxy("down", time.Hour), namedProxy("up"))
	testBalancer(t, selectorOver(t, "Pick", inner))

	delay := handleTestDelay(&TestDelayParams{ProxyName: "Balance", TestUrl: server.URL, Timeout: 2000})

	if delay == nil || delay.Value <= 0 {
		t.Errorf("delay = %+v, want the live member's under the selector's pick", delay)
	}
}

func TestABalancerMemberProbesEachTakeADelayTestSlot(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(noContentAfterAMillisecond))
	defer server.Close()
	entered := make(chan struct{}, 2)
	release := make(chan struct{})
	hold := func(ctx context.Context) error {
		entered <- struct{}{}
		select {
		case <-release:
			return nil
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	testBalancer(t, gatedProxy("a", hold), gatedProxy("b", hold))

	done := make(chan *Delay, 1)
	go func() {
		done <- handleTestDelay(&TestDelayParams{ProxyName: "Balance", TestUrl: server.URL, Timeout: 2000})
	}()
	for range 2 {
		select {
		case <-entered:
		case <-time.After(time.Second):
			t.Fatal("both members never started probing")
		}
	}
	held := len(delayTestSlots)
	close(release)
	<-done

	if held != 2 {
		t.Errorf("slots held while both members probe = %d, want 2", held)
	}
}

func TestABalancerTellsSameNamedMembersApart(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(noContentAfterAMillisecond))
	defer server.Close()
	testBalancer(t, laggingProxy("node", time.Hour), namedProxy("node"))

	delay := handleTestDelay(&TestDelayParams{ProxyName: "Balance", TestUrl: server.URL, Timeout: 2000})

	if delay == nil || delay.Value <= 0 {
		t.Errorf("delay = %+v, want the live one of two members named alike", delay)
	}
}

func TestABalancerLatticeProbesEachNodeOnce(t *testing.T) {
	probes := map[string]*atomic.Int32{}
	down := func(name string) constant.Proxy {
		probes[name] = &atomic.Int32{}
		return gatedProxy(name, func(context.Context) error {
			probes[name].Add(1)
			return errors.New("down")
		})
	}
	a, b := down("a"), down("b")
	shared := balanceOver(t, "Shared", a, b)
	testBalancer(t, balanceOver(t, "Left", shared, a), balanceOver(t, "Right", shared, b), selectorOver(t, "Pick", shared))

	if delay := handleTestDelay(&TestDelayParams{ProxyName: "Balance", TestUrl: "http://127.0.0.1:1", Timeout: 2000}); delay == nil || delay.Value != delayFailed {
		t.Fatalf("delay = %+v, want value %d", delay, delayFailed)
	}
	for name, count := range probes {
		if got := count.Load(); got != 1 {
			t.Errorf("%s probed %d times, want once however many groups reach it", name, got)
		}
	}
}

func TestABalancerAnswersWhenAMemberProbePanics(t *testing.T) {
	testBalancer(t,
		gatedProxy("panics", func(context.Context) error { panic("probe") }),
		gatedProxy("fails", func(context.Context) error { return errors.New("down") }),
	)

	done := make(chan *Delay, 1)
	go func() {
		done <- handleTestDelay(&TestDelayParams{ProxyName: "Balance", TestUrl: "http://127.0.0.1:1", Timeout: 2000})
	}()
	select {
	case delay := <-done:
		if delay != nil {
			t.Errorf("delay = %+v, want no verdict while a member's probe never finished", delay)
		}
	case <-time.After(time.Second):
		t.Fatal("the balancer kept waiting on the member whose probe panicked")
	}
}
