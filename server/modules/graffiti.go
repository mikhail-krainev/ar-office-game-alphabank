package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"image"
	"image/draw"
	"image/png"

	"github.com/heroiclabs/nakama-common/runtime"
)

// "Graffiti wall" (AR): one wall per office, shared by all its players. The player points the camera
// at a wall in the corridor, sees the graffiti everyone left before and sprays their own for 20
// seconds. The spray layer (a transparent PNG of the wall size) is the proof of the task: the server
// paints it over the office wall, so the next player sees it too. Newer paint covers older, like on a
// real wall. The admin sees who painted and can clean the wall (moderation).

const (
	graffitiMinigame   = "graffiti"
	graffitiCollection = "graffiti"
	graffitiWidth      = 144
	graffitiHeight     = 96
	graffitiMaxBytes   = 48 * 1024
	// A layer with fewer painted pixels is an empty wall, not a graffiti.
	graffitiMinPixels = 20
	// The admin sees this many last painters of a wall.
	graffitiMaxAuthors = 200
)

type graffitiAuthor struct {
	UserID string `json:"user_id"`
	T      int64  `json:"t"`
}

// graffitiWall: the office wall as everyone painted it, a base64 PNG, and who painted it.
type graffitiWall struct {
	PNG     string           `json:"png"`
	Tags    int              `json:"tags"`
	Authors []graffitiAuthor `json:"authors"`
}

// validGraffitiPNG: a PNG of graffitiWidth x graffitiHeight, at most graffitiMaxBytes, with some paint.
func validGraffitiPNG(encoded string) (image.Image, string) {
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil || len(data) == 0 || len(data) > graffitiMaxBytes {
		return nil, "graffiti_invalid"
	}
	config, err := png.DecodeConfig(bytes.NewReader(data))
	if err != nil || config.Width != graffitiWidth || config.Height != graffitiHeight {
		return nil, "graffiti_invalid"
	}
	layer, err := png.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, "graffiti_invalid"
	}
	if paintedPixels(layer) < graffitiMinPixels {
		return nil, "graffiti_empty"
	}
	return layer, ""
}

func paintedPixels(layer image.Image) int {
	count := 0
	bounds := layer.Bounds()
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			if _, _, _, alpha := layer.At(x, y).RGBA(); alpha > 0 {
				count++
			}
		}
	}
	return count
}

// paintOver: the wall with the layer painted over it; a missing wall is a clean one.
func paintOver(wall, layer image.Image) *image.NRGBA {
	bounds := image.Rect(0, 0, graffitiWidth, graffitiHeight)
	result := image.NewNRGBA(bounds)
	if wall != nil {
		draw.Draw(result, bounds, wall, image.Point{}, draw.Src)
	}
	draw.Draw(result, bounds, layer, image.Point{}, draw.Over)
	return result
}

// readGraffitiWall: the wall of the office and its storage version ("*" when nobody painted yet).
func readGraffitiWall(ctx context.Context, nk runtime.NakamaModule, office string) (graffitiWall, string, error) {
	objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{{Collection: graffitiCollection, Key: office, UserID: systemUserID}})
	if err != nil {
		return graffitiWall{}, "", errInternal
	}
	if len(objects) == 0 {
		return graffitiWall{}, "*", nil
	}
	var wall graffitiWall
	if err := json.Unmarshal([]byte(objects[0].GetValue()), &wall); err != nil {
		return graffitiWall{}, "", errInternal
	}
	return wall, objects[0].GetVersion(), nil
}

// paintGraffiti paints the player's layer over the wall of the office the player is in today. The
// write carries the read version: when another player painted meanwhile, the transaction runs again
// over the new wall, so no graffiti is lost.
func (tx *gameTx) paintGraffiti(layer image.Image) error {
	wall, version, err := readGraffitiWall(tx.ctx, tx.nk, tx.office())
	if err != nil {
		return err
	}
	var old image.Image
	if wall.PNG != "" {
		data, err := base64.StdEncoding.DecodeString(wall.PNG)
		if err != nil {
			return errInternal
		}
		if old, err = png.Decode(bytes.NewReader(data)); err != nil {
			return errInternal
		}
	}
	var encoded bytes.Buffer
	if err := png.Encode(&encoded, paintOver(old, layer)); err != nil {
		return errInternal
	}
	wall.PNG = base64.StdEncoding.EncodeToString(encoded.Bytes())
	wall.Tags++
	wall.Authors = append(wall.Authors, graffitiAuthor{UserID: tx.me.userID, T: tx.now})
	if len(wall.Authors) > graffitiMaxAuthors {
		wall.Authors = wall.Authors[len(wall.Authors)-graffitiMaxAuthors:]
	}
	return tx.writeSystem(graffitiCollection, tx.office(), wall, version)
}

// rpcGetGraffitiWall: {} -> {"png": base64 PNG or "", "tags", "error"}. The wall of the office the
// player is in now; only while the player is in the office (entry code scanned).
func rpcGetGraffitiWall(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, _ string) (string, error) {
	return runPlayerTx(ctx, logger, db, nk, func(tx *gameTx) (any, error) {
		if problem, err := tx.presenceError(); problem != "" || err != nil {
			return map[string]any{"png": "", "tags": 0, "error": problem}, err
		}
		wall, _, err := readGraffitiWall(tx.ctx, tx.nk, tx.office())
		if err != nil {
			return nil, err
		}
		return map[string]any{"png": wall.PNG, "tags": wall.Tags, "error": ""}, nil
	})
}

type graffitiRequest struct {
	OfficeID string `json:"office_id"`
}

// rpcAdminGetGraffiti: {"office_id"} -> graffitiWall. The admin checks what the players painted.
func rpcAdminGetGraffiti(ctx context.Context, logger runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	request, err := adminGraffitiRequest(ctx, nk, payload)
	if err != nil {
		return "", err
	}
	wall, _, err := readGraffitiWall(ctx, nk, request.OfficeID)
	if err != nil {
		logger.Error("read graffiti of %s: %v", request.OfficeID, err)
		return "", err
	}
	if wall.Authors == nil {
		wall.Authors = []graffitiAuthor{}
	}
	return encodeResponse(wall)
}

// rpcAdminClearGraffiti: {"office_id"} -> {"ok": true}. Cleans the office wall: everything painted
// on it is gone for every player.
func rpcAdminClearGraffiti(ctx context.Context, logger runtime.Logger, _ *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	request, err := adminGraffitiRequest(ctx, nk, payload)
	if err != nil {
		return "", err
	}
	if err := nk.StorageDelete(ctx, []*runtime.StorageDelete{{Collection: graffitiCollection, Key: request.OfficeID, UserID: systemUserID}}); err != nil {
		logger.Error("clear graffiti of %s: %v", request.OfficeID, err)
		return "", errInternal
	}
	logger.Info("graffiti wall of office %s cleaned", request.OfficeID)
	return encodeResponse(map[string]any{"ok": true})
}

func adminGraffitiRequest(ctx context.Context, nk runtime.NakamaModule, payload string) (graffitiRequest, error) {
	var request graffitiRequest
	if err := requireAdmin(ctx, nk); err != nil {
		return request, err
	}
	if err := decodePayload(payload, &request); err != nil {
		return request, err
	}
	if _, err := findOffice(ctx, nk, request.OfficeID); err != nil {
		return request, err
	}
	return request, nil
}
