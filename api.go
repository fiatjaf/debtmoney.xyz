package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/fiatjaf/accountd"
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

type ServerResponse struct {
	Ok bool `json:"ok"`
}

func handleGetUser(w http.ResponseWriter, r *http.Request) {
	userId := mux.Vars(r)["id"]
	if userId == "_me" {
		userId = logged(r)
	}

	user, err := ensureUser(userId)
	if err != nil {
		log.Warn().Err(err).Str("id", userId).Msg("failed to load account")
		jsonify(w, nil, err)
		return
	}

	// user balances
	user.Balances = make([]Balance, len(user.ha.Balances))

	for i, b := range user.ha.Balances {
		var assetName string
		if b.Asset.Type == "native" {
			// continue // should we display this?
			assetName = "XLM"
		} else {
			issuerName := b.Asset.Issuer
			err := pg.Get(&issuerName,
				"SELECT id FROM users WHERE address = $1",
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
			Limit:  b.Limit,
		}
	}

	// user records
	user.Records = []BaseRecord{}
	err = pg.Select(&user.Records, `
SELECT * FROM records
 WHERE description->>'to' = $1
    OR description->>'from' = $1
ORDER BY id
        `,
		user.Id)
	if err != nil {
		log.Error().Str("user", user.Id).Err(err).Msg("on user records query")
		err = nil
	}

	jsonify(w, user, err)
}

func handleGetRecord(w http.ResponseWriter, r *http.Request) {
	recordId, _ := strconv.Atoi(mux.Vars(r)["id"])

	var record BaseRecord
	err = pg.Get(&record, `
SELECT * FROM records
 WHERE id = $1
LIMIT 1
        `, recordId)
	if err != nil {
		log.Error().Int("record", recordId).Err(err).Msg("on get record")
	}

	jsonify(w, record, err)
}

func handleCreateDebt(w http.ResponseWriter, r *http.Request) {
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

	look, err := accountd.LookupUser(args.Creditor)
	if err != nil {
		jsonify(w, nil, err)
		return
	}

	var creditor string
	if look.Id != "" {
		// if the user has a known id, use it
		creditor = look.Id
	} else {
		// otherwise use the account with provider
		creditor = strings.ToLower(args.Creditor)
	}

	debt, err := me.createDebt(me.Id, creditor, args.Asset, args.Amount)
	if err != nil {
		log.Error().Err(err).Msg("failed to create debt")
		jsonify(w, nil, err)
		return
	}

	log.Debug().Int("id", debt.Id).Msg("debt created, should we confirm?")

	// will confirm automatically for the creditor if he is a registered user
	if look.Id != "" {
		var registered bool
		err = pg.Get(&registered, "SELECT true FROM users WHERE id = $1", look.Id)
		if err == nil && registered {
			r, _ := confirmRecord(debt.Id, look.Id) // ignore errors here by now
			err = maybePublish(r)

			if err != nil {
				jsonify(w, nil, err)
				return
			}
		}
	}

	jsonify(w, ServerResponse{true}, nil)
	return
}

func handleConfirm(w http.ResponseWriter, r *http.Request) {
	userId := logged(r)
	if userId == "" {
		jsonify(w, nil, errors.New("user not logged"))
		return
	}

	recordId, _ := strconv.Atoi(mux.Vars(r)["id"])
	record, err := confirmRecord(recordId, userId)
	if err != nil {
		jsonify(w, nil, err)
		return
	}

	err = maybePublish(record)

	jsonify(w, ServerResponse{true}, nil)
	return
}
