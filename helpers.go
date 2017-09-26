package main

import (
	"errors"
	"strings"
)

func decoupleNameSource(user string) (name, source string, err error) {
	parts := strings.Split(user, "@")
	if len(parts) != 2 {
		return "", "", errors.New("creditor must be an account <name>@<source>.")
	}
	name = parts[0]
	source = parts[1]
	return
}
