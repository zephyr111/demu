SRC_DIR = src
BIN_DIR = bin
TARGET = gba

DC=ldc2
OPT=-O -release #-O2 -s -frelease
SRCS = $(wildcard $(SRC_DIR)/*.d $(SRC_DIR)/interfaces/*.d)
OBJS = $(SRCS:%.d=%.o)
EXE_PATH = ./$(BIN_DIR)/$(TARGET)
CXXFLAGS = $(OPT) -I$(SRC_DIR) -I$(SRC_DIR)/interfaces -Ilib -Ilib/GtkD/src #-Wall
LDFLAGS = $(OPT) -L-Llib/derelict -L-Llib/GtkD -L-lderelict -L-lgtkd-3 -L-ldl


.PHONY: all run clean
.SUFFIXES:

all: $(EXE_PATH)

$(EXE_PATH): $(OBJS)
	$(DC) $^ -of $@ $(LDFLAGS)

%.o: %.d
	$(DC) -c $< -of $@ $(CXXFLAGS)

run: all
	$(EXE_PATH) "roms/cpu_instrs/01-special.gb"
	#roms/pokemon-silver.gbc

clean:
	$(RM) $(SRC_DIR)/*.o
	$(RM) $(SRC_DIR)/interfaces/*.o
	$(RM) $(EXE_PATH)

