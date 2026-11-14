# macOS build of the AppKit engine's object (docs/SIMPLE_BROWSER_SPEC.md, section 2). Usage: make -C Clib
# Elsewhere there is nothing to build here: Windows links webview.lib, and Linux's engine is a header.
ifeq ($(shell uname -s),Darwin)

CC ?= cc
CFLAGS ?= -O2 -g
CFLAGS += -fobjc-arc -Wall

sb_appkit.o: macos/sb_appkit.m macos/sb_appkit.h
	$(CC) $(CFLAGS) -c macos/sb_appkit.m -o sb_appkit.o

clean:
	rm -f sb_appkit.o

else

sb_appkit.o:
	@echo "simple_browser Clib: nothing to build here off macOS."

clean:
	@true

endif

.PHONY: clean
