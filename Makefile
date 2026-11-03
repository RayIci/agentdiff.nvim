NVIM ?= nvim
STYLUA ?= stylua

.PHONY: test fmt fmt-check helptags

## test: run the headless test suite (FILTER=name to run some spec files)
test:
	$(NVIM) --headless -u NONE -l tests/run.lua $(FILTER)

## fmt: format the Lua sources
fmt:
	$(STYLUA) lua tests bin

## fmt-check: check formatting without changing files
fmt-check:
	$(STYLUA) --check lua tests bin

## helptags: build doc/tags for :help agentdiff
helptags:
	$(NVIM) --headless -u NONE -c 'helptags doc' -c q
