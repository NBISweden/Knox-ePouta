# micromosler defs

alias ls='ls -h'
alias la='ls -a'
alias lla='ll -a'

[[ "$PATH" =~ "/usr/local/bin" ]] || export PATH=/usr/local/bin:$PATH

module () 
{ 
    return 0
}
export -f module
