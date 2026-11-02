UNAME_S := $(shell uname -s)

# Flags simples e compatíveis
CXXSTD   = -std=c++17
WARN     = -Wall

# Em Windows/MinGW, garanta exceptions (alguns builds podem herdar flags estranhas)
ifeq ($(UNAME_S),Linux)
  DLFLAGS = -ldl
  EXCFLAGS =
else
  DLFLAGS =
  EXCFLAGS = -fexceptions
endif

all:
	mkoctfile $(WARN) $(CXXSTD) $(EXCFLAGS) libretro_bridge.cpp $(DLFLAGS)

clean:
	rm -f libretro_bridge.oct libretro_bridge.mex* *.o
