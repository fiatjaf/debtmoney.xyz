package main

import (
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
