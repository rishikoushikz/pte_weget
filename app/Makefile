GO ?= go
BINARY = $(HOME)/.local/bin/weget

all: build

build:
	$(GO) build -ldflags="-s -w" -o $(BINARY) .

clean:
	rm -f $(BINARY)

run: build
	$(BINARY)
