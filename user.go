package main

import (
	"encoding/json"
	"strconv"
	"strings"

	"github.com/jmoiron/sqlx/types"
	"github.com/kr/pretty"
	"github.com/pkg/errors"
	"github.com/shopspring/decimal"
	b "github.com/stellar/go/build"
	"github.com/stellar/go/clients/horizon"
	"github.com/stellar/go/keypair"
)

type User struct {
	Id       string       `json:"id"       db:"id"`
	Address  string       `json:"address"  db:"address"`
	Seed     string       `json:"-"        db:"seed"`
	Balances []Balance    `json:"balances" db:"-"`
	Records  []BaseRecord `json:"records"  db:"-"`

	ha horizon.Account
}

func ensureUser(id string) (user User, err error) {
	id = strings.ToLower(id)

	txn, err := pg.Beginx()
	if err != nil {
		return
	}
	defer txn.Rollback()

	log.Info().Str("id", id).Msg("checking account existence")
	err = txn.Get(&user, `
SELECT * FROM users
 WHERE id = $1
    `, id)
	if err != nil && err.Error() != "sql: no rows in result set" {
		log.Error().Err(err).Msg("failed to find user")
		return
	}

	// load account info from stellar
	// runs no matter what
	defer func() {
		if err == nil {
			var ha horizon.Account
			ha, err = h.LoadAccount(user.Address)
			user.ha = ha
		}
	}()

	if user.Id != "" {
		// ok, we've found a row
		return
	}

	// proceed to create a new row
	log.Info().Str("id", id).Msg("creating account")
	pair, err := keypair.Random()
	if err != nil {
		log.Error().Err(err).Msg("failed to create keypair")
		return
	}

	_, err = txn.Exec(`
INSERT INTO users (id, address, seed)
VALUES ($1, $2, $3)
    `, id, pair.Address(), pair.Seed())
	if err != nil {
		log.Error().Err(err).Str("id", id).Msg("failed to create account on db")
		return
	}

	txn.Commit()

	user = User{
		Id:      id,
		Address: pair.Address(),
		Seed:    pair.Seed(),
	}
	err = user.fundInitial()
	if err != nil {
		return
	}

	return
}

func (user User) fundInitial() error {
	tx := b.Transaction(
		n,
		b.SourceAccount{s.SourceAddress},
		b.AutoSequence{h},
		b.CreateAccount(
			b.Destination{user.Address},
			b.NativeAmount{"20.1"},
		),
	)
	if tx.Err != nil {
		return tx.Err
	}

	txe := tx.Sign(s.SourceSeed)
	blob, err := txe.Base64()
	if err != nil {
		return err
	}

	_, err = h.SubmitTransaction(blob)
	if err != nil {
		return err
	}
	return nil
}

func (user User) fundMore(amount int) error {
	tx := b.Transaction(
		n,
		b.SourceAccount{s.SourceAddress},
		b.AutoSequence{h},
		b.Payment(
			b.Destination{user.Address},
			b.NativeAmount{strconv.Itoa(amount)},
		),
	)
	if tx.Err != nil {
		return tx.Err
	}

	txe := tx.Sign(s.SourceSeed)
	blob, err := txe.Base64()
	if err != nil {
		return err
	}

	_, err = h.SubmitTransaction(blob)
	if err != nil {
		return err
	}
	return nil
}

// create a new a trustline or add to an existing trustline so it fits `add`
func (rec User) trust(iss User, asset string, add string) error {
	add_, err := decimal.NewFromString(add)
	if err != nil {
		return err
	}

	zero := decimal.Decimal{}
	if add_.Equals(zero) {
		return nil
	}

	fund := true
	newTrust := add_

	for _, balance := range rec.ha.Balances {
		if balance.Asset.Issuer == iss.Address && balance.Asset.Code == asset {
			// asset already in the balance
			fund = false

			// adjust trustline amount
			limit, err1 := decimal.NewFromString(balance.Limit)
			balance, err2 := decimal.NewFromString(balance.Balance)
			if err1 != nil || err2 != nil {
				return errors.New("wrong balance values received from horizon")
			}
			free := limit.Sub(balance)
			if free.GreaterThan(add_) {
				// nothing to change
				return nil
			} else {
				newTrust = add_.Add(limit).Sub(free)
			}
		}
	}

	log.Info().
		Str("truster", rec.Id).
		Str("trustee", iss.Id).
		Str("newTrust", newTrust.String()).
		Bool("fund", fund).
		Msg("adjusting trustline")

	if fund {
		err := rec.fundMore(10)
		if err != nil {
			return err
		}
	}

	// change or create the trustline
	tx := b.Transaction(
		n,
		b.SourceAccount{rec.Address},
		b.AutoSequence{h},
		b.Trust(asset, iss.Address, b.Limit(newTrust.StringFixed(2))),
	)
	if tx.Err != nil {
		return tx.Err
	}

	txe := tx.Sign(rec.Seed)
	blob, err := txe.Base64()
	if err != nil {
		return err
	}

	_, err = h.SubmitTransaction(blob)
	if err != nil {
		if herr, ok := err.(*horizon.Error); ok {
			c, _ := herr.ResultCodes()
			pretty.Log(c)
		}
		return err
	}
	return nil
}

// create a new offer or add `add` to an existing offer
func (user User) offer(
	offerIss User, offerAsset string,
	requestIss User, requestAsset string,
	price, add string,
) error {
	add_, err := decimal.NewFromString(add)
	if err != nil {
		return err
	}

	zero := decimal.Decimal{}
	fund := true
	newOfferAmount := add_

	// load existing offers
	resp, err := h.LoadAccountOffers(user.Address)
	if err != nil {
		if herr, ok := err.(*horizon.Error); ok {
			c, _ := herr.ResultCodes()
			pretty.Log(c)
		}
		return err
	}

	for _, offer := range resp.Embedded.Records {
		if offer.Selling.Issuer == offerIss.Address &&
			offer.Selling.Code == offerAsset &&
			offer.Buying.Issuer == requestIss.Address &&
			offer.Buying.Code == requestAsset {
			// there is already an offer with these terms,
			fund = false

			// let's only change the amount and/or price
			if add_.Equals(zero) && offer.Price == price {
				// nothing to change
				return nil
			}

			newOfferAmount, err = decimal.NewFromString(offer.Amount)
			if err != nil {
				return err
			}
		}
	}

	log.Info().
		Str("user", user.Id).
		Str("offering", offerAsset+"#"+offerIss.Id).
		Str("requesting", requestAsset+"#"+requestIss.Id).
		Str("newOfferAmount", newOfferAmount.String()).
		Bool("fund", fund).
		Msg("adjusting offer")

	if newOfferAmount.Equals(zero) {
		return nil
	}

	if fund {
		err := user.fundMore(10)
		if err != nil {
			return err
		}
	}

	// change or create the trustline
	tx := b.Transaction(
		n,
		b.SourceAccount{user.Address},
		b.AutoSequence{h},
		b.CreateOffer(
			b.Rate{
				Selling: b.Asset{
					Code:   offerAsset,
					Issuer: offerIss.Address,
					Native: false,
				},
				Buying: b.Asset{
					Code:   requestAsset,
					Issuer: requestIss.Address,
					Native: false,
				},
				Price: b.Price(price),
			},
			b.Amount(newOfferAmount.StringFixed(2)),
		),
	)
	if tx.Err != nil {
		return tx.Err
	}

	txe := tx.Sign(user.Seed)
	blob, err := txe.Base64()
	if err != nil {
		return err
	}

	_, err = h.SubmitTransaction(blob)
	if err != nil {
		if herr, ok := err.(*horizon.Error); ok {
			c, _ := herr.ResultCodes()
			pretty.Log(c)
		}
		return err
	}
	return nil
}

func (me User) createDebt(from, to, assetCode, amount string) (*BaseRecord, error) {
	var r BaseRecord

	desc, _ := json.Marshal(Debt{
		From:   from,
		To:     to,
		Amount: amount,
	})

	err := pg.Get(&r, `
INSERT INTO records (kind, description, asset, confirmed)
VALUES ('debt', $1, $2, $3)
RETURNING *
    `, types.JSONText(desc), assetCode, StringSlice{me.Id})

	return &r, err
}

type Balance struct {
	Asset  string `json:"asset"`
	Amount string `json:"amount"`
	Limit  string `json:"limit"`
}
