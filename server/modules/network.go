package main

import (
	"context"
	"database/sql"
	"fmt"
	"net/netip"
	"strings"

	"github.com/heroiclabs/nakama-common/runtime"
)

// Office network: the second presence factor next to the entry code. The entry code, tasks, room
// codes and colleague picks count only when the request comes from an address of the player's
// office today (offices.go), so a player who checked in and went home cannot keep playing, and a
// player of one city cannot play from the network of another. The address comes from Nakama: the
// connection or the first X-Forwarded-For entry. Nakama trusts that header, so its port must be
// reachable only through a proxy that overwrites it (Caddy does by default).

// parseOfficeNetworks: comma-separated CIDR prefixes or single addresses.
func parseOfficeNetworks(value string) ([]netip.Prefix, error) {
	var networks []netip.Prefix
	for _, item := range strings.Split(value, ",") {
		item = strings.TrimSpace(item)
		if item == "" {
			continue
		}
		if !strings.Contains(item, "/") {
			addr, err := netip.ParseAddr(item)
			if err != nil {
				return nil, fmt.Errorf("OFFICE_NETWORKS: %q is not an address or a CIDR prefix", item)
			}
			addr = addr.Unmap()
			networks = append(networks, netip.PrefixFrom(addr, addr.BitLen()))
			continue
		}
		prefix, err := netip.ParsePrefix(item)
		if err != nil {
			return nil, fmt.Errorf("OFFICE_NETWORKS: %q is not an address or a CIDR prefix", item)
		}
		networks = append(networks, prefix.Masked())
	}
	return networks, nil
}

// inOfficeNetwork: the address is in one of the prefixes, or the check is off.
func inOfficeNetwork(networks []netip.Prefix, ip string) bool {
	if len(networks) == 0 {
		return true
	}
	addr, err := netip.ParseAddr(ip)
	if err != nil {
		return false
	}
	addr = addr.Unmap()
	for _, prefix := range networks {
		if prefix.Contains(addr) {
			return true
		}
	}
	return false
}

func (tx *gameTx) clientIP() string {
	ip, _ := tx.ctx.Value(runtime.RUNTIME_CTX_CLIENT_IP).(string)
	return ip
}

// networkError: "" or "office_network_required" when the request comes from outside the office
// the player counts in today (an office without a network does not check).
func (tx *gameTx) networkError() (string, error) {
	office, err := tx.currentOffice()
	if err != nil {
		return "", err
	}
	if office != nil && inOfficeNetwork(office.prefixes(), tx.clientIP()) {
		return "", nil
	}
	return "office_network_required", nil
}

// The whole game opens only in the office network: at home or on mobile internet every game RPC
// answers office_network_required, so nobody plays at home or on the way to the shop. Accounts and
// the admin panel work from anywhere, and so do these game RPCs:
var anywhereRpcs = map[string]bool{
	// Called when the game goes to the background, to plan reminders such as "check in today".
	"get_notification_plan": true,
	// Public pictures of colleagues.
	"get_avatar": true,
	// The office screen calls it with the server's HTTP key.
	"kiosk_codes": true,
	// "Go home" only closes the office interval, maybe already on the way home.
	"leave_office": true,
}

// Game RPCs that check the office network themselves instead of through officeOnly. A heartbeat
// from outside the network still closes the office visit (visits.go) before it is refused.
var selfCheckedRpcs = map[string]bool{
	"play_heartbeat": true,
}

var errOfficeNetwork = runtime.NewError("office_network_required", codePermissionDenied)

// gameRpc: an RPC of the game itself, which needs the office network (not admin, account or dev).
func gameRpc(id string) bool {
	if anywhereRpcs[id] || id == "get_profile" || id == "list_departments" || strings.HasPrefix(id, "admin_") || strings.HasPrefix(id, "dev_") {
		return false
	}
	return true
}

// officeOnly refuses the RPC outside the network of the caller's office today.
func officeOnly(fn rpcFunc) rpcFunc {
	return func(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
		allowed, err := callerInOfficeNetwork(ctx, nk)
		if err != nil {
			return "", err
		}
		if !allowed {
			return "", errOfficeNetwork
		}
		return fn(ctx, logger, db, nk, payload)
	}
}

func callerInOfficeNetwork(ctx context.Context, nk runtime.NakamaModule) (bool, error) {
	_, metadata, err := callerAccount(ctx, nk)
	if err != nil {
		return false, err
	}
	if metadata.Role != rolePlayer {
		// Game RPCs refuse other accounts themselves (not_player).
		return true, nil
	}
	officeID, _ := metadata.placement(dayOf(gameNow(), gameContent.officeOffset()))
	office, err := readOffice(ctx, nk, officeID)
	if err != nil || office == nil {
		return false, err
	}
	ip, _ := ctx.Value(runtime.RUNTIME_CTX_CLIENT_IP).(string)
	return inOfficeNetwork(office.prefixes(), ip), nil
}

// presenceError: why presence does not count now, or "" when the player is in today's office.
func (tx *gameTx) presenceError() (string, error) {
	if !tx.inMyOffice() {
		return "presence_required", nil
	}
	return tx.networkError()
}
