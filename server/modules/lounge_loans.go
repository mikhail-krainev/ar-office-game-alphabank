package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"strings"

	"github.com/heroiclabs/nakama-common/runtime"
)

const loansCollection = "lounge_loans"

type loungeLoan struct {
	ID           string `json:"id"`
	Borrower     string `json:"borrower"`
	BorrowerName string `json:"borrower_name"`
	Lender       string `json:"lender"`
	LenderName   string `json:"lender_name"`
	Amount       int64  `json:"amount"`
	Repaid       int64  `json:"repaid"`
	Status       string `json:"status"`
	Created      int64  `json:"created"`
}

func rpcLoungePeople(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var a struct {
		Search string `json:"search"`
	}
	if err := decodePayload(payload, &a); err != nil {
		return "", err
	}
	if len(a.Search) > 100 {
		return "", errInvalidPayload
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		rows, err := db.QueryContext(ctx, `SELECT id,display_name,username FROM users WHERE id<>$1 AND metadata->>'role'='player' AND disable_time=to_timestamp(0) AND (display_name ILIKE $2 OR username ILIKE $2) ORDER BY username LIMIT 30`, tx.me.userID, "%"+strings.TrimSpace(a.Search)+"%")
		if err != nil {
			return nil, errInternal
		}
		defer rows.Close()
		people := []any{}
		for rows.Next() {
			var id, name, username string
			if rows.Scan(&id, &name, &username) != nil {
				return nil, errInternal
			}
			people = append(people, map[string]string{"id": id, "name": name, "username": username})
		}
		if rows.Err() != nil {
			return nil, errInternal
		}
		return map[string]any{"ok": true, "people": people}, nil
	})
}
func rpcLoungeLoans(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var a struct {
		Action    string `json:"action"`
		ID        string `json:"id"`
		UserID    string `json:"user_id"`
		Amount    int64  `json:"amount"`
		Operation string `json:"operation_key"`
	}
	if err := decodePayload(payload, &a); err != nil {
		return "", err
	}
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if a.Action == "list" {
			reads := []*runtime.StorageRead{}
			for _, id := range tx.me.state.LoanIDs {
				reads = append(reads, &runtime.StorageRead{Collection: loansCollection, Key: id, UserID: systemUserID})
			}
			loans := []loungeLoan{}
			if len(reads) > 0 {
				objects, err := nk.StorageRead(ctx, reads)
				if err != nil {
					return nil, errInternal
				}
				for _, o := range objects {
					var l loungeLoan
					if json.Unmarshal([]byte(o.GetValue()), &l) != nil {
						return nil, errInternal
					}
					if l.Borrower == tx.me.userID || l.Lender == tx.me.userID {
						loans = append(loans, l)
					}
				}
			}
			return map[string]any{"ok": true, "loans": loans, "balance": tx.me.balance}, nil
		}
		claimed, err := tx.claimOperation(a.Operation)
		if err != nil {
			return nil, err
		}
		if !claimed {
			return fail("duplicate_operation"), nil
		}
		var loan loungeLoan
		version := "*"
		if a.Action == "request" {
			if err := tx.pruneClosedLoanIndex(tx.me); err != nil {
				return nil, err
			}
			if a.UserID == tx.me.userID || a.Amount < 1 || a.Amount > 1000000 || len(tx.me.state.LoanIDs) >= 200 {
				return fail("invalid_loan"), nil
			}
			lender, err := tx.other(a.UserID)
			if err != nil {
				return nil, err
			}
			if err := tx.pruneClosedLoanIndex(lender); err != nil {
				return nil, err
			}
			if lender.banned() || lender.metadata.Role != rolePlayer || len(lender.state.LoanIDs) >= 200 {
				return fail("player_unavailable"), nil
			}
			loan = loungeLoan{ID: randomKey(), Borrower: tx.me.userID, BorrowerName: tx.me.displayName(), Lender: lender.userID, LenderName: lender.displayName(), Amount: a.Amount, Status: "pending", Created: tx.now}
			tx.me.state.LoanIDs = append(tx.me.state.LoanIDs, loan.ID)
			lender.state.LoanIDs = append(lender.state.LoanIDs, loan.ID)
			if _, err := tx.notify(lender, "loan_request", map[string]any{"name": loan.BorrowerName, "amount": loan.Amount}, ""); err != nil {
				return nil, err
			}
		} else {
			if len(a.ID) > 64 || a.ID == "" {
				return nil, errInvalidPayload
			}
			objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{{Collection: loansCollection, Key: a.ID, UserID: systemUserID}})
			if err != nil {
				return nil, errInternal
			}
			if len(objects) == 0 {
				return fail("loan_not_found"), nil
			}
			if json.Unmarshal([]byte(objects[0].GetValue()), &loan) != nil {
				return nil, errInternal
			}
			version = objects[0].GetVersion()
			switch a.Action {
			case "accept", "decline":
				if loan.Lender != tx.me.userID || loan.Status != "pending" {
					return fail("invalid_loan"), nil
				}
				if a.Action == "decline" {
					loan.Status = "declined"
				} else {
					if tx.me.balance < loan.Amount {
						return fail("not_enough_coins"), nil
					}
					borrower, err := tx.other(loan.Borrower)
					if err != nil {
						return nil, err
					}
					if borrower.banned() {
						return fail("player_unavailable"), nil
					}
					tx.credit(tx.me, -loan.Amount, "loan_lend", loan.ID)
					tx.credit(borrower, loan.Amount, "loan_receive", loan.ID)
					loan.Status = "accepted"
				}
			case "repay":
				if loan.Borrower != tx.me.userID || loan.Status != "accepted" || a.Amount < 1 || a.Amount > loan.Amount-loan.Repaid {
					return fail("invalid_loan"), nil
				}
				if tx.me.balance < a.Amount {
					return fail("not_enough_coins"), nil
				}
				lender, err := tx.other(loan.Lender)
				if err != nil {
					return nil, err
				}
				tx.credit(tx.me, -a.Amount, "loan_repay", loan.ID)
				tx.credit(lender, a.Amount, "loan_repaid", loan.ID)
				loan.Repaid += a.Amount
				if loan.Repaid == loan.Amount {
					loan.Status = "repaid"
				}
			default:
				return fail("invalid_action"), nil
			}
		}
		if err := tx.writeSystem(loansCollection, loan.ID, loan, version); err != nil {
			return nil, err
		}
		return map[string]any{"ok": true, "loan": loan, "balance": tx.me.balance}, nil
	})
}

// The cap limits outstanding loans, not a player's lifetime use. Closed records remain in
// system storage and the wallet ledger, but no longer fill the active profile index indefinitely.
func (tx *gameTx) pruneClosedLoanIndex(doc *playerDoc) error {
	if len(doc.state.LoanIDs) < 200 {
		return nil
	}
	reads := make([]*runtime.StorageRead, 0, len(doc.state.LoanIDs))
	for _, id := range doc.state.LoanIDs {
		reads = append(reads, &runtime.StorageRead{Collection: loansCollection, Key: id, UserID: systemUserID})
	}
	objects, err := tx.nk.StorageRead(tx.ctx, reads)
	if err != nil {
		return errInternal
	}
	open := map[string]bool{}
	for _, object := range objects {
		var loan loungeLoan
		if json.Unmarshal([]byte(object.GetValue()), &loan) != nil {
			return errInternal
		}
		if loan.Status == "pending" || loan.Status == "accepted" {
			open[loan.ID] = true
		}
	}
	kept := []string{}
	for _, id := range doc.state.LoanIDs {
		if open[id] {
			kept = append(kept, id)
		}
	}
	doc.state.LoanIDs = kept
	return nil
}
