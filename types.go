package main

type User struct {
	Name string `json:"name"`
}

type Balance struct {
	Asset  string `json:"asset"`
	Amount int    `json:"amount"`
}
