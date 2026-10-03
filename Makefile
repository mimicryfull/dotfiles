.PHONY: all install status add sync unlink dry-run help

all: install

install:
	@./install.sh

status:
	@./install.sh status

dry-run:
	@./install.sh --dry-run

unlink:
	@./install.sh unlink

help:
	@./install.sh --help
