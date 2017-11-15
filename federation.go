package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"github.com/stellar/go/protocols/federation"
)

func fed(w http.ResponseWriter, r *http.Request) {
	qs := r.URL.Query()
	q := qs.Get("q")
	typ := qs.Get("type")

	switch typ {
	case "name":
		splitted := strings.Split(q, "*")
		if len(splitted) != 2 {
			http.Error(
				w,
				"send a proper name: user*debtmoney.xyz",
				http.StatusBadRequest,
			)
			return
		}

		if splitted[1] != "debtmoney.xyz" {
			http.Error(
				w,
				fmt.Sprintf("'%s' is not controlled by this server", splitted[1]),
				http.StatusBadRequest,
			)
			return
		}

		var addr string
		pg.Get(&addr, "SELECT address FROM users WHERE id = $1", splitted[0])

		if addr == "" {
			http.Error(
				w,
				fmt.Sprintf("'%s' is not known", splitted[0]),
				http.StatusNotFound,
			)
			return
		}

		json.NewEncoder(w).Encode(federation.NameResponse{
			AccountID: addr,
		})
	case "id":
		var userId string
		pg.Get(&userId, "SELECT id FROM users WHERE address = $1", q)

		if userId == "" {
			http.Error(
				w,
				fmt.Sprintf("'%s' is not known", q),
				http.StatusNotFound,
			)
			return
		}

		json.NewEncoder(w).Encode(federation.IDResponse{
			Address: userId + "*debtmoney.xyz",
		})
	case "forward":
		http.Error(w, "forward type queries are not supported", http.StatusNotImplemented)
	case "txid":
		http.Error(w, "txid type queries are not supported", http.StatusNotImplemented)
	default:
		http.Error(w, fmt.Sprintf("invalid type: '%s'", typ), http.StatusBadRequest)
	}
}
