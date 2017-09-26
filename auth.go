package main

import (
	"errors"
	"net/http"
	"strings"

	"golang.org/x/crypto/openpgp"
)

func keybaseAuth(message string) (user string, valid bool, err error) {
	content, signature, err := parseSigned(message)
	if err != nil {
		return
	}

	user = content
	w, err := http.Get("https://keybase.io/" + content + "/key.asc")
	if err != nil {
		return
	}

	keyring, err := openpgp.ReadArmoredKeyRing(w.Body)
	if err != nil {
		return
	}

	entity, err := openpgp.CheckArmoredDetachedSignature(
		keyring,
		strings.NewReader(content),
		strings.NewReader(signature),
	)
	if err != nil {
		return
	}

	for _, identity := range entity.Identities {
		valid = "keybase.io/"+content == identity.UserId.Name
		return
	}

	return user, false, errors.New("bizarre openpgp verifying error.")
}

func parseSigned(message string) (content, signature string, err error) {
	lines := strings.Split(message, "\n")
	for i, line := range lines {
		if strings.Index(line, "-----BEGIN PGP SIGNATURE-----") != -1 {
			content = lines[i-1]
			signature = strings.Join(lines[i:], "\n")
			return
		}
	}
	return "", "", errors.New("invalid clearsigned signed message + signature.")
}
