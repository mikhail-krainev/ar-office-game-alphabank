package main

import (
	crand "crypto/rand"
	"math/big"
)

// Table randomness comes straight from the operating system's CSPRNG: every card and every roulette
// pocket is an independent draw with no seed or generator state that earlier results could reveal.

// secureIntN: uniform integer in [0, n) without modulo bias.
func secureIntN(n int) int {
	value, err := crand.Int(crand.Reader, big.NewInt(int64(n)))
	if err != nil {
		// A table must never fall back to a guessable source such as the clock.
		panic("lounge: system randomness is unavailable: " + err.Error())
	}
	return int(value.Int64())
}

// secureShuffle: Fisher–Yates over n items, every permutation equally likely.
func secureShuffle(n int, swap func(i, j int)) {
	for i := n - 1; i > 0; i-- {
		swap(i, secureIntN(i+1))
	}
}
