SRC_DIR = src
BIN_DIR = bin
TARGET = gba

# Choose automatically the compiler if not specified
ifndef DC
    ifneq ($(strip $(shell which ldc2 2>/dev/null)),)
        DC=ldc2
    else
        DC=gdc
    endif
endif

# Select the options according to the compiler
ifeq ($(DC),ldc2)
    OPT_LTO=-flto=full -flto-binary=/usr/lib/llvm-5.0/lib/LLVMgold.so
    OPT_DFLAGS=$(OPT_LTO) -O3 -ffast-math -release -mcpu=native
    OPT_LDFLAGS=$(OPT_LTO) -O3 -ffast-math -release
else
	# LTO buggy with gcc 7 or not implemented ?
    OPT_LTO=#-flto=full
    OPT_DFLAGS=$(OPT_LTO) -O3 -ffast-math -s -frelease -march=native
    OPT_LDFLAGS=$(OPT_LTO) -O3 -ffast-math -frelease
endif

SRCS = $(wildcard $(SRC_DIR)/*.d $(SRC_DIR)/interfaces/*.d)
OBJS = $(SRCS:%.d=%.o)
EXE_PATH = ./$(BIN_DIR)/$(TARGET)
ifeq ($(VERSION), )
    VERSION_INFOS=
else
    VERSION_INFOS=-d-version=$(VERSION)
endif

ifeq ($(DC),ldc2)
    DFLAGS = $(VERSION_INFOS) $(OPT_DFLAGS) -I$(SRC_DIR) -I$(SRC_DIR)/interfaces -Ilib -Ilib/GtkD/generated/gtkd #-Wall
    LDFLAGS = $(OPT_LDFLAGS) -L-Llib/derelict -L-Llib/GtkD -L-lderelict -L-lgtkd-3 -L-ldl
else
    DFLAGS = $(VERSION_INFOS) $(OPT_DFLAGS) -I$(SRC_DIR) -I$(SRC_DIR)/interfaces -Ilib -Ilib/GtkD/generated/gtkd #-Wall
    LDFLAGS = $(OPT_LDFLAGS) -Llib/derelict -Llib/GtkD -lderelict -lgtkd-3 -ldl
endif


.PHONY: all run clean
.SUFFIXES:

all: $(EXE_PATH)

ifeq ($(DC),ldc2)
$(EXE_PATH): $(OBJS)
	$(DC) $^ -of $@ $(LDFLAGS)

%.o: %.d
	$(DC) -c $< -of $@ $(DFLAGS)
else
$(EXE_PATH): $(OBJS)
	$(DC) $^ -o $@ $(LDFLAGS)

%.o: %.d
	$(DC) -c $< -o $@ $(DFLAGS)
endif

run: all
	$(EXE_PATH) "roms/cpu_instrs/01-special.gb"
	#roms/pokemon-silver.gbc

clean:
	$(RM) $(SRC_DIR)/*.o
	$(RM) $(SRC_DIR)/interfaces/*.o
	$(RM) $(EXE_PATH)

