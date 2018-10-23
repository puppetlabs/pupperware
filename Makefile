TOPDIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

services: lb puppetserver puppetdb

lb:
	@echo build local/lb
	@docker build -q --network=host -t local/lb $(TOPDIR)/services/lb

puppetserver:
	@echo build local/puppetserver
	@docker build -q -t local/puppetserver $(TOPDIR)/services/puppetserver

puppetdb:
	@echo build local/puppetdb
	@docker build -q -t local/puppetdb $(TOPDIR)/services/puppetdb

.PHONY: lb puppetserver puppetdb
