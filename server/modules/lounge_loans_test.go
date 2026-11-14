package main

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"

	"github.com/heroiclabs/nakama-common/api"
	"github.com/heroiclabs/nakama-common/runtime"
)

type loanIndexStorage struct {
	runtime.NakamaModule
	objects []*api.StorageObject
}

func (s loanIndexStorage) StorageRead(context.Context, []*runtime.StorageRead) ([]*api.StorageObject, error) {
	return s.objects, nil
}

func TestClosedLoansDoNotExhaustLifetimeBorrowing(t *testing.T) {
	doc := &playerDoc{state: &PlayerState{}}
	storage := loanIndexStorage{}
	for i := 0; i < 200; i++ {
		id := fmt.Sprintf("loan-%d", i)
		status := "repaid"
		if i == 198 {
			status = "accepted"
		}
		if i == 199 {
			status = "pending"
		}
		value, _ := json.Marshal(loungeLoan{ID: id, Status: status})
		storage.objects = append(storage.objects, &api.StorageObject{Key: id, Value: string(value)})
		doc.state.LoanIDs = append(doc.state.LoanIDs, id)
	}
	tx := &gameTx{nk: storage}
	if err := tx.pruneClosedLoanIndex(doc); err != nil {
		t.Fatal(err)
	}
	if len(doc.state.LoanIDs) != 2 || doc.state.LoanIDs[0] != "loan-198" || doc.state.LoanIDs[1] != "loan-199" {
		t.Fatalf("outstanding loans lost or old loans retained: %v", doc.state.LoanIDs)
	}
}
