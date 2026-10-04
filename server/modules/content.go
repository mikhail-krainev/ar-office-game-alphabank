package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// Game content from server/content, loaded once at start. The client gets it only through RPCs.

type Task struct {
	ID          string         `json:"id"`
	Title       string         `json:"title"`
	Description string         `json:"description"`
	Room        string         `json:"room"`
	Floor       string         `json:"floor"`
	Spot        []int          `json:"spot"`
	Minigame    string         `json:"minigame"`
	Fallback    string         `json:"fallback"`
	Params      map[string]any `json:"params"`
	Assignment  string         `json:"assignment"`
	Reward      int            `json:"reward"`
	Difficulty  string         `json:"difficulty"`
	Skippable   bool           `json:"skippable"`
	// Hidden tasks never get into a pack, e.g. while their minigame works badly.
	Hidden bool `json:"hidden,omitempty"`
}

type CatalogItem struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Rarity      string `json:"rarity"`
	Price       int    `json:"price"`
	Icon        int    `json:"icon"`
}

type WardrobeUnlock struct {
	Type string `json:"type"`
	Item string `json:"item"`
	Days int    `json:"days"`
}

type WardrobeEntry struct {
	Slot   string          `json:"slot"`
	ID     string          `json:"id"`
	Name   string          `json:"name"`
	Unlock *WardrobeUnlock `json:"unlock"`
}

type Car struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Price       int    `json:"price"`
	SpeedKmh    int    `json:"speed_kmh"`
}

type FineTier struct {
	Days    int `json:"days"`
	Percent int `json:"percent"`
}

type Rules struct {
	Office struct {
		ID               string `json:"id"`
		UTCOffsetMinutes int    `json:"utc_offset_minutes"`
	} `json:"office"`
	Attendance struct {
		FineTiers      []FineTier `json:"fine_tiers"`
		MaxCatchUpDays int        `json:"max_catch_up_days"`
	} `json:"attendance"`
	Notifications struct {
		ReminderTimes []string   `json:"reminder_times"`
		FunWindows    [][]string `json:"fun_windows"`
		FunMax        int        `json:"fun_max"`
	} `json:"notifications"`
	Photo struct {
		PartnerBonus int `json:"partner_bonus"`
	} `json:"photo"`
	Raffle struct {
		PrizeName        string `json:"prize_name"`
		PrizeDescription string `json:"prize_description"`
		TicketPrice      int    `json:"ticket_price"`
		MinOfficeDays    int    `json:"min_office_days"`
		WindowDays       int    `json:"window_days"`
		DrawHour         int    `json:"draw_hour"`
		DrawMinute       int    `json:"draw_minute"`
	} `json:"raffle"`
	Economy struct {
		WelcomeBonus         int     `json:"welcome_bonus"`
		DailyCoinCap         int     `json:"daily_coin_cap"`
		MaxScoreBonus        float64 `json:"max_score_bonus"`
		StreakMultiplierStep float64 `json:"streak_multiplier_step"`
		MaxStreakMultiplier  float64 `json:"max_streak_multiplier"`
	} `json:"economy"`
	Limits          Limits   `json:"limits"`
	AvatarTemplates []string `json:"avatar_templates"`
}

type Content struct {
	Tasks    []Task
	Catalog  []CatalogItem
	Wardrobe []WardrobeEntry
	Cars     []Car
	FunTexts []string
	Rules    Rules
}

func loadContent(dir string) (*Content, error) {
	var content Content
	var tasks struct {
		Tasks []Task `json:"tasks"`
	}
	var catalog struct {
		Items []CatalogItem `json:"items"`
	}
	var wardrobe struct {
		Items []WardrobeEntry `json:"items"`
	}
	var cars struct {
		Cars []Car `json:"cars"`
	}
	var notifications struct {
		Fun []string `json:"fun"`
	}
	files := map[string]any{
		"tasks.json":         &tasks,
		"shop_catalog.json":  &catalog,
		"wardrobe.json":      &wardrobe,
		"cars.json":          &cars,
		"notifications.json": &notifications,
		"game_rules.json":    &content.Rules,
	}
	for name, target := range files {
		data, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			return nil, err
		}
		if err := json.Unmarshal(data, target); err != nil {
			return nil, fmt.Errorf("%s: %w", name, err)
		}
	}
	if err := validateLimits(content.Rules.Limits); err != nil {
		return nil, fmt.Errorf("game_rules.json: limits: %w", err)
	}
	content.Tasks = tasks.Tasks
	content.Catalog = catalog.Items
	content.Wardrobe = wardrobe.Items
	content.Cars = cars.Cars
	content.FunTexts = notifications.Fun
	for i := range content.Tasks {
		if content.Tasks[i].Floor == "" {
			content.Tasks[i].Floor = "hq"
		}
		if _, ok := difficultyMultipliers[content.Tasks[i].Difficulty]; !ok {
			content.Tasks[i].Difficulty = "normal"
		}
		if content.Tasks[i].Params == nil {
			content.Tasks[i].Params = map[string]any{}
		}
	}
	return &content, nil
}

func (c *Content) task(id string) *Task {
	for i := range c.Tasks {
		if c.Tasks[i].ID == id {
			return &c.Tasks[i]
		}
	}
	return nil
}

func (c *Content) car(id string) *Car {
	for i := range c.Cars {
		if c.Cars[i].ID == id {
			return &c.Cars[i]
		}
	}
	return nil
}

func (c *Content) wardrobeItem(slot, id string) *WardrobeEntry {
	for i := range c.Wardrobe {
		if c.Wardrobe[i].Slot == slot && c.Wardrobe[i].ID == id {
			return &c.Wardrobe[i]
		}
	}
	return nil
}

// wardrobeSlots lists the outfit slots in the order they first appear in wardrobe.json.
func (c *Content) wardrobeSlots() []string {
	slots := []string{}
	seen := map[string]bool{}
	for _, entry := range c.Wardrobe {
		if !seen[entry.Slot] {
			seen[entry.Slot] = true
			slots = append(slots, entry.Slot)
		}
	}
	return slots
}

func (c *Content) isAvatarTemplate(id string) bool {
	for _, template := range c.Rules.AvatarTemplates {
		if template == id {
			return true
		}
	}
	return false
}

func (c *Content) officeOffset() int64 {
	return int64(c.Rules.Office.UTCOffsetMinutes) * 60
}
