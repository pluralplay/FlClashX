package core

import (
	"os"
	"regexp"
	"strings"
	"testing"

	"github.com/dlclark/regexp2"
)

func TestValidateFiltersReadsEachBacktickPart(t *testing.T) {
	results := handleValidateFilters([]string{
		"",
		"(?i)港|(?<![a-z])hk(?![a-z])",
		"hk`jp",
		"[a-z-[aeiou]]",
		"(abc",
		"hk`(",
	})
	for i, valid := range []bool{true, true, true, true, false, false} {
		if (results[i] == "") != valid {
			t.Errorf("filter %d: got %q, want valid=%v", i, results[i], valid)
		}
	}
}

var presetEntry = regexp.MustCompile(`Filter\(\s*label:\s*'([^']*)',\s*regex:\s*((?:r'[^']*'\s*)+),?\s*\)`)
var rawString = regexp.MustCompile(`r'([^']*)'`)

func filterPresets(t *testing.T) map[string]string {
	t.Helper()
	source, err := os.ReadFile("../lib/models/config.dart")
	if err != nil {
		t.Fatal(err)
	}
	_, body, _ := strings.Cut(string(source), "const defaultFilters = [")
	body, _, _ = strings.Cut(body, "\n];")
	presets := map[string]string{}
	for _, entry := range presetEntry.FindAllStringSubmatch(body, -1) {
		var pattern strings.Builder
		for _, part := range rawString.FindAllStringSubmatch(entry[2], -1) {
			pattern.WriteString(part[1])
		}
		presets[entry[1]] = pattern.String()
	}
	if len(presets) == 0 {
		t.Fatal("found no presets; the parser lost track of defaultFilters")
	}
	return presets
}

func TestFilterPresetsMatchTheirNamesOnly(t *testing.T) {
	matches := map[string][]string{
		"Hong Kong":         {"🇭🇰 HK 01", "Hong Kong-02", "Гонконг 1"},
		"Taiwan":            {"🇹🇼 TW", "Taiwan 03", "Тайвань 2"},
		"Japan":             {"JP01", "Tokyo 2", "Япония 1", "Токио"},
		"Singapore":         {"SG-1", "Singapore", "Сингапур"},
		"United States":     {"US 01", "USA", "United States 2", "США"},
		"South Korea":       {"KR 1", "South Korea", "Корея"},
		"United Kingdom":    {"UK-London", "GB 2", "Британия", "Лондон"},
		"Remaining Traffic": {"Traffic: 10 GB", "Remaining 1 TB", "Трафик: 10 ГБ", "Осталось 20 ГБ"},
		"Expiry Date":       {"Expire: 2026-12-31", "Expiration 2026-12-31", "Истекает 31.12", "Срок: 2026-12-31"},
		"Traffic Reset":     {"Next Reset: 12 days", "Сброс через 12 дней"},
		"Website & Notices": {"Website: example.com", "Telegram", "TG канал", "Сайт: example.com"},
	}
	misses := map[string][]string{
		"Hong Kong":         {"CHKS 1", "Japan 01"},
		"United States":     {"Russia 01", "Australia", "Plus"},
		"United Kingdom":    {"Ukraine 01"},
		"Remaining Traffic": {"Hong Kong 01", "US Premium", "HK Fast"},
		"Expiry Date":       {"Hong Kong 01", "Japan 01"},
		"Traffic Reset":     {"Hong Kong 01", "US Reserved"},
		"Website & Notices": {"Hong Kong 01", "US Montgomery", "Taiwan 01"},
	}
	presets := filterPresets(t)
	for name := range matches {
		if _, ok := presets[name]; !ok {
			t.Errorf("preset %s is gone from defaultFilters", name)
		}
	}
	for name, pattern := range presets {
		if _, ok := matches[name]; !ok {
			t.Errorf("preset %s has no sample names here", name)
			continue
		}
		reg, err := regexp2.Compile(pattern, regexp2.None)
		if err != nil {
			t.Errorf("preset %s: %v", name, err)
			continue
		}
		for _, sample := range matches[name] {
			if ok, _ := reg.MatchString(sample); !ok {
				t.Errorf("preset %s misses %q", name, sample)
			}
		}
		for _, sample := range misses[name] {
			if ok, _ := reg.MatchString(sample); ok {
				t.Errorf("preset %s matches %q", name, sample)
			}
		}
	}
}
