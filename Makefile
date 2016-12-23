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

LATEX:=pdflatex --shell-escape
BIBTEX:=bibtex -terse

.SUFFIXES: .pdf .tex .txt .bb .map .enc .ttf .vf .tfm
.PHONY: all scripts sections misc img

## ==== Thesis ==================================================
all: _build/$(TARGET).pdf

e:
	@make ERROR=yes

_build:
	@mkdir -p $@

_build/$(TARGET).pdf: $(TARGET).tex _build $(SOURCES) 
	@echo Compiling $(TARGET).tex
	@$(LATEX) $(FLAGS) -output-directory=$(@D) $< $(REDIRECT)

force: _build
	@echo "Compiling $(TARGET).tex [forcing]"
	@$(LATEX) $(FLAGS) -output-directory=$(@D) $(TARGET).tex $(REDIRECT)

final: $(TARGET).tex _build $(SOURCES) bib
	@echo "Second compilation"
	@$(LATEX) $(FLAGS) -output-directory=_build $< $(REDIRECT)
	@echo "Final compilation"
	@$(LATEX) $(FLAGS) -output-directory=_build $< $(REDIRECT)

## ==== Bibtex ==================================================
# Must use the TEXMFOUTPUT variable or change the openout_any=a in the texmf.cnf settings file
_build/$(TARGET).bbl: misc/references.bib _build _build/$(TARGET).aux
	@echo "Compiling the bibliography"
	@export TEXMFOUTPUT=_build; $(BIBTEX) _build/$(TARGET) || true
_build/$(TARGET).aux: _build/$(TARGET).pdf
bib: _build/$(TARGET).bbl


# =============================================================================
# PICTURES
# =============================================================================
PICS=controller compute-node overview

pics: $(PICS:%=_build/img/%.pdf)

cleanpics: 
	@rm -rf _build/img

_build/img/%.pdf: img/%.tex _build settings/styles.tex
	@mkdir -p $(@D)
	@echo "Compiling $*"
	@$(LATEX) $(FLAGS) -output-directory=$(@D) --jobname $* "\documentclass{standalone}\input{settings/main}\begin{document}\input{$<}\end{document}" $(REDIRECT)

_build/img/%.png: _build/img/%.pdf
	@echo "Converting $(@F) to PNG"
	@sips -Z 1024 -s format png $< --out $@ &>/dev/null


# =============================================================================
# Cleaning
# =============================================================================
cleantilde:
	@find . -type f -iname '*~' -exec  rm {} \;

clean: cleantilde
	@rm -f _build/$(TARGET).*

cleanall: cleantilde
	@rm -rf _build

