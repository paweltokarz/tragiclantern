MODEL = 750D
FW_VERSION = 110

TOP_DIR = ../..

AUTOEXEC_BASE = 0x800000
FIR_BASE = 0x800120

#CANON_FIR = 750D0110.FIR
FIRMWARE_ID = 0x80000393
#UPDATE_NAME_FIR = CCF23110.FIR
MAIN_FIRMWARE_ADDR = 0xFE0A0000

# user_mem_start from cstart struct. Align to 0x10 up
RESTARTSTART = 0x001cc400

# Cortex R4
CFLAGS_PLATFORM += -mthumb -mlong-calls
PLATFORM_ARCH = armv7-r

ML_BOOT_OBJ = boot-d678.o
ML_SRC_EXTRA_OBJS += $(BUILD_DIR)/function_overrides.o

# PTP experiment, phase 1:
# - build Canon PTP core plus CHDK file-transfer handlers into autoexec
# - do not auto-register from early ML init on 750D yet
# - keep the Debug menu diagnostic visible
#
# platform/Makefile sets CONFIG_PTP* defaults after this file is included,
# so 750D must force these values explicitly for default platform builds.
override CONFIG_PTP = y
override CONFIG_PTP_CHDK = y
override CONFIG_PTP_ML = n
override CONFIG_PTP_NO_AUTO_INIT = y
override CONFIG_PTP_MANUAL_MENU = y

include ../Makefile

# 750D Lua package policy:
# keep only the final user-facing exposure bracket script in ML/scripts.
# Keep scripts/lib/*.lua because Lua runtime uses the library path.
.PHONY: 750d_lua_scripts_only

zip_contents:: 750d_lua_scripts_only

750d_lua_scripts_only: $(ZIP_DIR)
	@echo "750D: keeping only expo_bracket_750d.lua in ML/scripts"
	find $(BUILD_DIR)/zip/ML/scripts -maxdepth 1 -type f -name '*.lua' ! -name 'expo_bracket_750d.lua' -delete
	test -f $(BUILD_DIR)/zip/ML/scripts/expo_bracket_750d.lua
	test -f $(BUILD_DIR)/zip/ML/scripts/lib/strict.lua

.DEFAULT_GOAL := $(BUILD_DIR)/cam_complete
