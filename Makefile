SHELL := /bin/bash

.PHONY: help

help:
	@echo 'The Go core and Rust helper build automatically through the setup build'
	@echo 'hook during flutter build; see .agents/commands.md. mihomo comes from'
	@echo 'the Go module cache (core/go.mod), there is no submodule to update.'
