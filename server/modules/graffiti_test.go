package main

import (
	"bytes"
	"encoding/base64"
	"image"
	"image/color"
	"image/png"
	"testing"
)

func encodeLayer(width, height, painted int, paint color.NRGBA) string {
	layer := image.NewNRGBA(image.Rect(0, 0, width, height))
	for index := 0; index < painted; index++ {
		layer.SetNRGBA(index%width, index/width, paint)
	}
	var buffer bytes.Buffer
	_ = png.Encode(&buffer, layer)
	return base64.StdEncoding.EncodeToString(buffer.Bytes())
}

func TestGraffitiLayerMustFitTheWallAndHavePaint(t *testing.T) {
	red := color.NRGBA{R: 239, G: 49, B: 36, A: 255}
	if _, problem := validGraffitiPNG(encodeLayer(graffitiWidth, graffitiHeight, 50, red)); problem != "" {
		t.Errorf("a valid graffiti rejected: %s", problem)
	}
	if _, problem := validGraffitiPNG(encodeLayer(graffitiWidth, graffitiHeight, graffitiMinPixels-1, red)); problem != "graffiti_empty" {
		t.Errorf("an empty wall: problem = %q", problem)
	}
	cases := map[string]string{
		"wrong size": encodeLayer(graffitiWidth, graffitiHeight+1, 50, red),
		"empty":      "",
		"garbage":    "not base64!",
	}
	for name, encoded := range cases {
		if _, problem := validGraffitiPNG(encoded); problem != "graffiti_invalid" {
			t.Errorf("%s: problem = %q", name, problem)
		}
	}
}

func TestNewGraffitiCoversTheOldAndKeepsTheRest(t *testing.T) {
	red := color.NRGBA{R: 255, A: 255}
	blue := color.NRGBA{B: 255, A: 255}
	old := image.NewNRGBA(image.Rect(0, 0, graffitiWidth, graffitiHeight))
	old.SetNRGBA(0, 0, red)
	old.SetNRGBA(1, 0, red)
	layer := image.NewNRGBA(image.Rect(0, 0, graffitiWidth, graffitiHeight))
	layer.SetNRGBA(1, 0, blue)
	layer.SetNRGBA(2, 0, blue)
	wall := paintOver(old, layer)
	for x, want := range []color.NRGBA{red, blue, blue, {}} {
		if got := wall.NRGBAAt(x, 0); got != want {
			t.Errorf("pixel %d = %v, want %v", x, got, want)
		}
	}
	if got := paintOver(nil, layer).NRGBAAt(2, 0); got != blue {
		t.Errorf("a clean wall: pixel = %v", got)
	}
}
