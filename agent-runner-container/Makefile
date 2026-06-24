# agent-runner — thin sugar over the canonical `nix run .#<app>` interface.
# Nix owns the build contract; these targets just save keystrokes.

IMAGE ?= agent-runner:latest

.DEFAULT_GOAL := up
.PHONY: up build run root test clean help

## up:    build (cached) then drop into the container — the one-shot path
up:
	nix run .#up

## build: build the image via Nix-orchestrated Docker build
build:
	nix run .#build-image

## run:   launch the container without rebuilding
run:
	nix run .#run

## root:  open a root shell in the running container
root:
	nix run .#root

## test:  smoke-test the built image
test:
	nix run .#test-image

## clean: remove the image and reclaim all build cache (full reset)
clean:
	-docker rmi $(IMAGE)
	-docker image prune --force
	-docker builder prune --force

## help:  list targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
