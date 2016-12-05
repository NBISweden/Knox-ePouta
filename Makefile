SOURCES := $(wildcard settings/*.tex) settings/*.cls main.tex \
	   $(wildcard sections/*.tex) $(wildcard img/*.tex) sections/references.bib

ERROR ?= no 
ifeq ($(ERROR),yes)
FLAGS?=-interaction=errorstopmode -file-line-error -halt-on-error
REDIRECT?=
else
FLAGS?=-interaction=batchmode
REDIRECT?= > /dev/null
endif

export TEXMFVAR = settings
LATEX := pdflatex --shell-escape
BIBTEX := bibtex -terse
MAKEINDEX := makeindex -q
CURRDIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
BUILD := $(CURRDIR)_build

.SUFFIXES: .pdf .tex .txt .bb .map .enc .ttf .vf .tfm
.PHONY: all web img experiments force

## ==== Thesis ==================================================
all: $(BUILD)/main.pdf

e:
	@make ERROR=yes

$(BUILD)/main.pdf: main.tex settings/builddir.tex $(SOURCES) 
	@echo Compiling main.tex
	@$(LATEX) $(FLAGS) -output-directory=$(BUILD) $< $(REDIRECT)

force:
	@echo "Compiling main.tex [forcing]"
	@$(LATEX) $(FLAGS) -output-directory=$(BUILD) main.tex $(REDIRECT)

final: main.tex settings/builddir.tex $(SOURCES) bib index
	@echo "Second compilation"
	@$(LATEX) $(FLAGS) -output-directory=$(BUILD) $< $(REDIRECT)
	@echo "Final compilation"
	@$(LATEX) $(FLAGS) -output-directory=$(BUILD) $< $(REDIRECT)

## ==== Bibtex ==================================================
# Must use the TEXMFOUTPUT variable or change the openout_any=a in the texmf.cnf settings file
$(BUILD)/main.bbl: misc/references.bib $(BUILD)/main.aux
	@echo "Compiling the bibliography"
	@export TEXMFOUTPUT=$(BUILD); $(BIBTEX) $(BUILD)/main || true
$(BUILD)/main.aux: $(BUILD)/main.pdf
bib: $(BUILD)/main.bbl

settings/builddir.tex:
	@mkdir $(BUILD)
	@echo "\\\newcommand\\\builddir{\detokenize{$(BUILD)}}" > $@
#	@for c in {parameterized-systems,verification,monotonic-abstraction,view-abstraction,shape-analysis}; do mkdir -p $(BUILD)/chapters/$${c}; done

# =============================================================================
# Cleaning
# =============================================================================
cleantilde:
	@find . -type f -iname '*~' -exec  rm {} \;

clean: cleantilde
	@rm -f $(BUILD)/main.*

cleanall: cleantilde
	@rm -rf $(BUILD)
	@rm -f settings/builddir.tex

