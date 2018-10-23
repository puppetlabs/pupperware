TOPDIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

services: puppetserver puppetdb

puppetserver:
	@echo build local/puppetserver
	@docker build -q -t local/puppetserver $(TOPDIR)/services/puppetserver

puppetdb:
	@echo build local/puppetdb
	@docker build -q -t local/puppetdb $(TOPDIR)/services/puppetdb

.PHONY: puppetserver puppetdb
