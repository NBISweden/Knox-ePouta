#!/usr/bin/env python
# -*- coding: utf-8 -*-


from jinja2 import Environment, FileSystemLoader
import os
import sys

# Capture our current directory
THIS_DIR = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = sys.argv[1]

def get_script():
    # Create the jinja2 environment.
    # Controlling whitespace with trim_blocks.
    j2_env = Environment(loader=FileSystemLoader(THIS_DIR), trim_blocks=True)
    return j2_env.get_template(TEMPLATE).render(env=os.environ)
    
if __name__ == '__main__':
    #sys.stdout.write(print_script())
    print get_script()
