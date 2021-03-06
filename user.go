package main

import (
	"errors"
	"strconv"

	"github.com/shopspring/decimal"
	b "github.com/stellar/go/build"
	"github.com/stellar/go/clients/horizon"
	"github.com/stellar/go/keypair"
)

type User struct {
	Id           string `json:"id"            db:"id"`
	Address      string `json:"address"       db:"address"`
	Seed         string `json:"-"             db:"seed"`
	DefaultAsset string `json:"default_asset" db:"default_asset"`

	ha horizon.Account `json:"-"`
}

func (u User) columns() string {
	return `
coalesce(users.id, '') AS id,
coalesce(users.address, '') AS address,
coalesce(users.seed, '') AS seed,
coalesce(users.default_asset, 'USD') AS default_asset
    `
}

type Path struct {
	Src  Asset   `json:"src_asset"`
	Dst  Asset   `json:"dst_asset"`
	Path []Asset `json:"path"`
}

type Balance struct {
	Asset  Asset  `json:"asset"`
	Amount string `json:"amount"`
	Limit  string `json:"limit"`
}

type Asset struct {
	Code          string `json:"code"`
	IssuerAddress string `json:"issuer_address"`
	IssuerId      string `json:"issuer_id"`
}

func ensureUser(id string) (user User, err error) {
	if id == "" {
		err = errors.New("blank user id")
		return
	}

	log.Info().Str("id", id).Msg("ensuring account")
	pair, err := keypair.Random()
	if err != nil {
		log.Warn().Err(err).Msg("failed to create keypair")
		return
	}

	err = pg.Get(&user, `
WITH ins AS (
  INSERT INTO users (id, address, seed)
  VALUES (lower($1), $2, $3)
  ON CONFLICT DO NOTHING
)

SELECT `+user.columns()+` FROM users WHERE id = $1
    `, id, pair.Address(), pair.Seed())
	if err != nil {
		log.Warn().Err(err).Str("id", id).Msg("failed to create user on db")
		return
	}

	return
}

func getExistingUser(id string) (user User, err error) {
	err = pg.Get(&user, "SELECT "+user.columns()+" FROM users WHERE id = $1", id)
	if err != nil && err.Error() != "sql: no rows in result set" {
		log.Warn().Err(err).Str("id", id).Msg("failed to load user on db")
	}
	return
}

func (user User) fundInitial(amount int) b.TransactionMutator {
	return b.CreateAccount(
		b.SourceAccount{s.SourceAddress},
		b.Destination{user.Address},
		b.NativeAmount{strconv.Itoa(amount)},
	)
}

func (user User) fund(amount int) b.TransactionMutator {
	if amount <= 0 {
		return b.Defaults{}
	}

	return b.Payment(
		b.SourceAccount{s.SourceAddress},
		b.Destination{user.Address},
		b.NativeAmount{strconv.Itoa(amount)},
	)
}

// create a new a trustline or add to an existing trustline so it fits `add`
func (rec User) trust(
	iss User,
	asset string,
	add string,
) (fund bool, mutator b.TransactionMutator, didtrust bool, err error) {
	add_, err := decimal.NewFromString(add)
	if err != nil {
		return false, b.Defaults{}, false, err
	}

	zero := decimal.Decimal{}
	if add_.Equals(zero) {
		return false, b.Defaults{}, false, nil
	}

	fund = true
	newTrust := add_

	for _, balance := range rec.ha.Balances {
		if balance.Asset.Issuer == iss.Address && balance.Asset.Code == asset {
			// asset already in the balance
			fund = false

			// adjust trustline amount
			limit, err := decimal.NewFromString(balance.Limit)
			if err != nil {
				log.Warn().Err(err).
					Str("limit", balance.Limit).
					Msg("wrong values received from horizon")
				return false, b.Defaults{}, false, err
			}

			decimalbalance, err := decimal.NewFromString(balance.Balance)
			if err != nil {
				log.Warn().Err(err).
					Str("balance", balance.Balance).
					Msg("wrong values received from horizon")
				return false, b.Defaults{}, false, err
			}
			free := limit.Sub(decimalbalance)
			if free.GreaterThan(add_) {
				// nothing to change
				return false, b.Defaults{}, false, nil
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

	return fund,
		b.Trust(
			asset,
			iss.Address,
			b.Limit(newTrust.StringFixed(2)),
			b.SourceAccount{rec.Address},
		),
		true,
		nil
}

// create a new offer or add `add` to an existing offer
func (user User) offer(
	offerIss User, offerAsset string,
	requestIss User, requestAsset string,
	price, add string,
) (bool, b.TransactionMutator, error) {
	add_, err := decimal.NewFromString(add)
	if err != nil {
		return false, b.Defaults{}, err
	}

	var existingOffer b.OfferID
	zero := decimal.Decimal{}
	fund := true
	newOfferAmount := add_

	// load existing offers
	resp, err := h.LoadAccountOffers(user.Address)
	if err != nil {
		if herr, ok := err.(*horizon.Error); ok {
			log.Warn().
				Err(err).Str("herr", formatHorizonError(herr)).
				Msg("loading existing offers for account")
		}
		return false, b.Defaults{}, err
	}

	for _, offer := range resp.Embedded.Records {
		if offer.Selling.Issuer == offerIss.Address &&
			offer.Selling.Code == offerAsset &&
			offer.Buying.Issuer == requestIss.Address &&
			offer.Buying.Code == requestAsset {
			// there is already an offer with these terms,
			existingOffer = b.OfferID(offer.ID)
			fund = false

			// let's only change the amount and/or price
			if add_.Equals(zero) && offer.Price == price {
				// nothing to change
				return false, b.Defaults{}, nil
			}

			newOfferAmount, err = decimal.NewFromString(offer.Amount)
			if err != nil {
				return false, b.Defaults{}, err
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
		return false, b.Defaults{}, nil
	}

	return fund,
		b.ManageOffer(
			false,
			b.SourceAccount{user.Address},
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
			existingOffer, // if zero will create a new offer, no problem.
		),
		nil
}
