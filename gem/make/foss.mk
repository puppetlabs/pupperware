SELF_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
include $(SELF_DIR)/common.mk

NAMESPACE ?= puppet
LATEST_VERSION ?= latest
