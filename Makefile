TARGET := main
SOURCES := $(wildcard settings/*.tex) settings/*.cls $(TARGET).tex \
	   $(wildcard sections/*.tex) misc/references.bib $(wildcard img/*.tex) \
	   $(wildcard scripts/*.sh) $(wildcard misc/*.tex)

ERROR ?= no 
ifeq ($(ERROR),yes)
FLAGS?=-interaction=errorstopmode -file-line-error -halt-on-error
REDIRECT?=
else
FLAGS?=-interaction=batchmode
REDIRECT?= > /dev/null
endif

LATEX := pdflatex --shell-escape
BIBTEX := bibtex -terse
CURRDIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
BUILD := $(CURRDIR)_build

.SUFFIXES: .pdf .tex .txt .bb .map .enc .ttf .vf .tfm
.PHONY: all web img experiments force

## ==== Thesis ==================================================
all: $(BUILD)/$(TARGET).pdf

e:
	@make ERROR=yes

$(BUILD)/$(TARGET).pdf: $(TARGET).tex settings/builddir.tex $(SOURCES) 
	@echo Compiling $(TARGET).tex
	@$(LATEX) $(FLAGS) -output-directory=$(BUILD) $< $(REDIRECT)

force:
	@echo "Compiling $(TARGET).tex [forcing]"
	@$(LATEX) $(FLAGS) -output-directory=$(BUILD) $(TARGET).tex $(REDIRECT)

final: $(TARGET).tex settings/builddir.tex $(SOURCES) bib
	@echo "Second compilation"
	@$(LATEX) $(FLAGS) -output-directory=$(BUILD) $< $(REDIRECT)
	@echo "Final compilation"
	@$(LATEX) $(FLAGS) -output-directory=$(BUILD) $< $(REDIRECT)

## ==== Bibtex ==================================================
# Must use the TEXMFOUTPUT variable or change the openout_any=a in the texmf.cnf settings file
$(BUILD)/$(TARGET).bbl: misc/references.bib $(BUILD)/$(TARGET).aux
	@echo "Compiling the bibliography"
	@export TEXMFOUTPUT=$(BUILD); $(BIBTEX) $(BUILD)/$(TARGET) || true
$(BUILD)/$(TARGET).aux: $(BUILD)/$(TARGET).pdf
bib: $(BUILD)/$(TARGET).bbl

settings/builddir.tex:
	@mkdir -p $(BUILD)
	@echo "\\\newcommand\\\builddir{\detokenize{$(BUILD)}}" > $@

# =============================================================================
# Cleaning
# =============================================================================
cleantilde:
	@find . -type f -iname '*~' -exec  rm {} \;

clean: cleantilde
	@rm -f $(BUILD)/$(TARGET).*

cleanall: cleantilde
	@rm -rf $(BUILD)
	@rm -f settings/builddir.tex

