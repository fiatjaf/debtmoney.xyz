package main

import (
	"strconv"

	"github.com/pkg/errors"
	"github.com/shopspring/decimal"

	b "github.com/stellar/go/build"
	"github.com/stellar/go/clients/horizon"
	"github.com/stellar/go/keypair"
)

type Account struct {
	Name   string `json:"name"`
	Source string `json:"source"`
	Public string `json:"public"`
	Secret string `json:"-"`

	horizon.Account
}

func ensureAccount(name, source string) (acc Account, err error) {
	txn, err := pg.Beginx()
	if err != nil {
		return
	}
	defer txn.Rollback()

	err = txn.Get(&acc, `
SELECT * FROM accounts
WHERE name = $1 AND source = $2
    `, name, source)
	if err != nil && err.Error() != "sql: no rows in result set" {
		return
	}

	// load account info from stellar
	// runs no matter what
	defer func() {
		if err == nil {
			var ha horizon.Account
			ha, err = testnet.LoadAccount(acc.Public)
			acc.Account = ha
		}
	}()

	if acc.Name != "" {
		// ok, we've found a row
		return
	}

	// proceed to create a new row
	pair, err := keypair.Random()
	if err != nil {
		return
	}

	_, err = txn.Exec(`
INSERT INTO accounts
(name, source, public, secret)
VALUES ($1, $2, $3, $4)
    `, name, source, pair.Address(), pair.Seed())
	if err != nil {
		return
	}

	txn.Commit()

	acc = Account{
		Name:   name,
		Source: source,
		Public: pair.Address(),
		Secret: pair.Seed(),
	}
	err = acc.fundInitial()
	if err != nil {
		return
	}

	return
}

func (acc Account) fundInitial() error {
	tx := b.Transaction(
		b.TestNetwork,
		b.SourceAccount{s.SourcePublic},
		b.AutoSequence{testnet},
		b.CreateAccount(
			b.Destination{acc.Public},
			b.NativeAmount{"20.1"},
		),
	)
	if tx.Err != nil {
		return tx.Err
	}

	txe := tx.Sign(s.SourceSecret)
	blob, err := txe.Base64()
	if err != nil {
		return err
	}

	_, err = testnet.SubmitTransaction(blob)
	if err != nil {
		return err
	}
	return nil
}

func (acc Account) fundMore(amount int) error {
	tx := b.Transaction(
		b.TestNetwork,
		b.SourceAccount{s.SourcePublic},
		b.AutoSequence{testnet},
		b.Payment(
			b.Destination{acc.Public},
			b.NativeAmount{strconv.Itoa(amount)},
		),
	)
	if tx.Err != nil {
		return tx.Err
	}

	txe := tx.Sign(s.SourceSecret)
	blob, err := txe.Base64()
	if err != nil {
		return err
	}

	_, err = testnet.SubmitTransaction(blob)
	if err != nil {
		return err
	}
	return nil
}

func (rec Account) trust(iss Account, asset string, newAmount string) error {
	newAmountd, err := decimal.NewFromString(newAmount)
	if err != nil {
		return err
	}

	zero := decimal.Decimal{}
	fund := true
	need := newAmountd

	for _, balance := range rec.Balances {
		if balance.Asset.Issuer == iss.Public && balance.Asset.Code == asset {
			// asset already in the balance
			fund = false

			// adjust trustline amount
			limit, err1 := decimal.NewFromString(balance.Limit)
			balance, err2 := decimal.NewFromString(balance.Balance)
			if err1 != nil || err2 != nil {
				return errors.New("wrong balance values received from horizon")
			}
			free := limit.Sub(balance)
			if free.GreaterThan(newAmountd) {
				need = zero
			}
		}
	}

	if need.Equals(zero) {
		return nil
	}

	if fund {
		err := rec.fundMore(10)
		if err != nil {
			return err
		}
	}

	// change or create the trustline
	tx := b.Transaction(
		b.TestNetwork,
		b.SourceAccount{rec.Public},
		b.AutoSequence{testnet},
		b.Trust(asset, iss.Public, b.Limit(need.StringFixed(2))),
	)
	if tx.Err != nil {
		return tx.Err
	}

	txe := tx.Sign(rec.Secret)
	blob, err := txe.Base64()
	if err != nil {
		return err
	}

	_, err = testnet.SubmitTransaction(blob)
	if err != nil {
		return err
	}
	return nil
}

func (from Account) makeDebt(to Account, assetCode string, amount string) error {
	tx := b.Transaction(
		b.TestNetwork,
		b.SourceAccount{from.Public},
		b.AutoSequence{testnet},
		b.Payment(
			b.Destination{to.Public},
			b.CreditAmount{assetCode, from.Public, amount},
		),
	)
	if tx.Err != nil {
		return tx.Err
	}

	txe := tx.Sign(from.Secret)
	blob, err := txe.Base64()
	if err != nil {
		return err
	}

	_, err = testnet.SubmitTransaction(blob)
	if err != nil {
		return err
	}
	return nil
}

type Balance struct {
	Asset  string `json:"asset"`
	Amount string `json:"amount"`
}
