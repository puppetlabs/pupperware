SELF_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
include $(SELF_DIR)/common.mk

NAMESPACE ?= artifactory.delivery.puppetlabs.net/pe-and-platform
VERSION ?= `jq '."ubuntu-18.04-amd64"."pe-puppetserver"."version"' $(PWD)/tmp/enterprise-dist/packages.json 2> /dev/null | tr -d '"'`
RELEASE ?= `jq '."ubuntu-18.04-amd64"."pe-puppetserver"."release"' $(PWD)/tmp/enterprise-dist/packages.json 2> /dev/null | tr -d '"'`
LATEST_VERSION ?= kearney-latest

prep: cleanup
	@git fetch --unshallow 2> /dev/null ||:
	@git fetch origin 'refs/tags/*:refs/tags/*'
	@mkdir -p $(PWD)/tmp
ifeq ($(TRAVIS),true)
	@git clone --quiet --single-branch --branch 2019.1.x --depth=1 https://github.com/puppetlabs/enterprise-dist $(PWD)/tmp/enterprise-dist
else ifneq ($(DISTELLI_BUILDNUM),)
	@git clone --quiet --single-branch --branch 2019.1.x --depth=1 https://$$GITHUB_TOKEN@github.com/puppetlabs/enterprise-dist $(PWD)/tmp/enterprise-dist
else
	@git clone --quiet --single-branch --branch 2019.1.x --depth=1 git@github.com:puppetlabs/enterprise-dist $(PWD)/tmp/enterprise-dist
endif

cleanup:
	@rm -rf $(PWD)/tmp/enterprise-dist/
	@rmdir $(PWD)/tmp 2> /dev/null ||: # remove the tmp dir if it's empty
