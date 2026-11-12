package core

import (
	"bytes"

	"github.com/metacubex/mihomo/config"
	"go.yaml.in/yaml/v3"
)

// mihomo decodes an unquoted REALITY short-id as a YAML number (0123 is 83, 00
// is 0); the scalar keeps its literal text, so retagging it restores the id.
func unmarshalRawConfig(buf []byte) (*config.RawConfig, error) {
	if !bytes.Contains(buf, []byte("short-id")) {
		return config.UnmarshalRawConfig(buf)
	}
	var document yaml.Node
	if yaml.Unmarshal(buf, &document) != nil || !retagShortIDs(&document) {
		return config.UnmarshalRawConfig(buf)
	}
	rawConfig := config.DefaultRawConfig()
	if err := document.Decode(rawConfig); err != nil {
		return nil, err
	}
	return rawConfig, nil
}

func retagShortIDs(node *yaml.Node) bool {
	retagged := false
	if node.Kind == yaml.MappingNode {
		for i := 0; i+1 < len(node.Content); i += 2 {
			if node.Content[i].Value == "short-id" {
				value, changed := retagShortID(node.Content[i+1])
				node.Content[i+1] = value
				retagged = changed || retagged
			}
		}
	}
	for _, child := range node.Content {
		retagged = retagShortIDs(child) || retagged
	}
	return retagged
}

// A copy is retagged: an alias's target may be another key's value, such as a port.
func retagShortID(node *yaml.Node) (*yaml.Node, bool) {
	target := resolveAlias(node)
	if target.Kind != yaml.SequenceNode {
		return retagNumber(node)
	}
	retagged := false
	items := make([]*yaml.Node, len(target.Content))
	for i, item := range target.Content {
		var changed bool
		items[i], changed = retagNumber(item)
		retagged = changed || retagged
	}
	if !retagged {
		return node, false
	}
	copied := *target
	copied.Anchor, copied.Content = "", items
	return &copied, true
}

func retagNumber(node *yaml.Node) (*yaml.Node, bool) {
	target := resolveAlias(node)
	if target.Kind != yaml.ScalarNode || target.Style != 0 || (target.Tag != "!!int" && target.Tag != "!!float") {
		return node, false
	}
	copied := *target
	copied.Anchor, copied.Tag = "", "!!str"
	return &copied, true
}
