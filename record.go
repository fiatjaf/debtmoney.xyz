package main

import (
	"database/sql/driver"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/jmoiron/sqlx/types"
)

type Record interface {
	Confirm(string) error
	Publish() error
}

type BaseRecord struct {
	Id           int            `json:"-"            db:"id"`
	CreatedAt    time.Time      `json:"created_at"   db:"created_at"`
	RecordDate   time.Time      `json:"record_date"  db:"record_date"`
	Kind         string         `json:"kind"         db:"kind"`
	Asset        string         `json:"asset"        db:"asset"`
	Description  types.JSONText `json:"description"  db:"description"`
	Confirmed    StringSlice    `json:"confirmed"    db:"confirmed"`
	Transactions StringSlice    `json:"transactions" db:"transactions"`
}

type StringSlice []string

func (stringSlice StringSlice) Value() (driver.Value, error) {
	var quotedStrings []string
	for _, str := range stringSlice {
		quotedStrings = append(quotedStrings, strconv.Quote(str))
	}
	value := fmt.Sprintf("{ %s }", strings.Join(quotedStrings, ","))
	return value, nil
}

func (stringSlice *StringSlice) Scan(src interface{}) error {
	val, ok := src.([]byte)
	if !ok {
		return fmt.Errorf("unable to scan")
	}
	value := strings.TrimPrefix(string(val), "{")
	value = strings.TrimSuffix(value, "}")

	*stringSlice = strings.Split(value, ",")

	return nil
}
