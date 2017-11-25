package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	b "github.com/stellar/go/build"
	"github.com/stellar/go/clients/horizon"
	"github.com/stellar/go/xdr"
)

func createStellarTransaction() *b.TransactionBuilder {
	return b.Transaction(
		n,
		b.SourceAccount{s.SourceAddress},
		b.AutoSequence{h},
	)
}

func commitStellarTransaction(
	tx *b.TransactionBuilder,
	signers ...string,
) (hash string, err error) {
	tx.TX.Fee = xdr.Uint32(100 * len(tx.TX.Operations))

	if tx.Err != nil {
		log.Warn().Err(err).Msg("failed to build transaction")
		return "", tx.Err
	}

	txe := tx.Sign(signers...)
	blob, err := txe.Base64()
	if err != nil {
		log.Warn().Err(err).Msg("failed to sign transaction")
		return "", err
	}

	success, err := h.SubmitTransaction(blob)
	if err != nil {
		var herrmsg string
		if herr, ok := err.(*horizon.Error); ok {
			herrmsg = formatHorizonError(herr)
		}
		log.Warn().
			Err(err).Str("herr", herrmsg).
			Str("xdr", blob).
			Msg("failed to execute transaction")
		return "", err
	}

	return success.Hash, nil
}

func formatHorizonError(herr *horizon.Error) string {
	c, err := herr.ResultCodes()
	if c == nil {
		return err.Error()
	}
	return /* herr.Problem.Detail + ". " + */ c.TransactionCode + ": [ " + strings.Join(c.OperationCodes, ", ") + " ]"
}

func findPaths(
	from_address string,
	to_address string,
	to_asset Asset,
) (data HorizonPathResponse, err error) {
	qs := url.Values{}

	qs.Set("source_account", from_address)
	qs.Set("destination_account", to_address)
	qs.Set("destination_asset_type", "credit_alphanum4")
	qs.Set("destination_asset_code", to_asset.Code)
	qs.Set("destination_asset_issuer", to_asset.IssuerAddress)
	qs.Set("destination_amount", "1")

	var resp *http.Response
	resp, err = http.Get(h.URL + "/paths?" + qs.Encode())
	if err != nil {
		return
	}
	if resp.StatusCode >= 300 {
		err = errors.New("Horizon returned status " + strconv.Itoa(resp.StatusCode))
	}

	err = json.NewDecoder(resp.Body).Decode(&data)
	return
}

type HorizonPathResponse struct {
	Embedded struct {
		Records []struct {
			SrcAssetCode   string `json:"source_asset_code"`
			SrcAssetIssuer string `json:"source_asset_issuer"`
			Intermediaries []struct {
				Code   string `json:"asset_code"`
				Issuer string `json:"asset_issuer"`
			} `json:"path"`
			DstAssetCode   string `json:"destination_asset_code"`
			DstAssetIssuer string `json:"destination_asset_issuer"`
		} `json:"records"`
	} `json:"_embedded"`
}
