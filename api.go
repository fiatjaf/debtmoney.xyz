package main

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/gorilla/mux"
)

func logged(r *http.Request) string {
	session, err := sessionStore.Get(r, "auth-session")
	if err != nil {
		return ""
	}

	if userId, ok := session.Values["userId"]; ok {
		return userId.(string)
	}

	return ""
}

func jsonify(w http.ResponseWriter, value interface{}, err error) {
	if err != nil {
		http.Error(w, err.Error(), 516)
		return
	}

	v, err := json.Marshal(value)
	if err != nil {
		http.Error(w, err.Error(), 523)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(v)
}

func getUser(w http.ResponseWriter, r *http.Request) {
	userId := mux.Vars(r)["id"]
	if userId == "_me" {
		userId = logged(r)
	}

	user, err := ensureUser(userId)

	// user balances
	user.Balances = make([]Balance, len(user.ha.Balances)-1)

	for i, b := range user.ha.Balances {
		var assetName string
		if b.Asset.Type == "native" {
			continue
		} else {
			issuerName := b.Asset.Issuer
			err := pg.Get(&issuerName,
				"SELECT name || '@' || source FROM userounts WHERE public = $1",
				b.Asset.Issuer)
			if err != nil {
				log.Error().
					Str("issuer", b.Asset.Issuer).
					Err(err).
					Msg("on asset issuer name query.")
			}
			assetName = b.Asset.Code + "#" + issuerName
		}

		user.Balances[i] = Balance{
			Asset:  assetName,
			Amount: b.Balance,
		}
	}

	// user records
	err = pg.Select(&user.Records, `
SELECT * FROM records
WHERE description->>'to' = $1
   OR description->>'from' = $1
        `,
		user.Id)
	if err != nil {
		log.Error().Str("user", user.Id).Err(err).Msg("on user records query")
		err = nil
	}

	jsonify(w, user, err)
}

func createDebt(w http.ResponseWriter, r *http.Request) {
	userId := logged(r)
	if userId == "" {
		jsonify(w, nil, errors.New("user not logged"))
		return
	}
	me, err := ensureUser(userId)
	if err != nil {
		jsonify(w, nil, err)
		return
	}

	var args struct {
		Creditor string `json:"creditor"`
		Asset    string `json:"asset"`
		Amount   string `json:"amount"`
	}
	if err = json.NewDecoder(r.Body).Decode(&args); err != nil {
		jsonify(w, nil, err)
		return
	}

	log.Info().
		Str("from", me.Id).
		Str("to", args.Creditor).
		Str("asset", args.Asset).
		Str("amount", args.Amount).
		Msg("looking up creditor")

	look, err := lookupUser(args.Creditor)
	if err != nil {
		jsonify(w, nil, err)
		return
	}

	var cred User
	if look.Id != "" {
		cred, err = ensureUser(look.Id)
		if err != nil {
			jsonify(w, nil, err)
			return
		}
	}

	debt, err := me.simpleDebt(me.Id, args.Creditor, args.Asset, args.Amount)
	if err != nil {
		jsonify(w, nil, err)
		return
	}

	log.Info().Int("id", debt.Id).Msg("debt created, should we confirm?")

	if look.Id != "" {
		debt.From = me
		debt.To = cred
		err = debt.Confirm(look.Id)
	}

	jsonify(w, nil, err)
	return
}
