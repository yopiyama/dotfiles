# -*- encoding: utf-8 -*-
# Python startup file
# https://dackdive.hateblo.jp/entry/2014/08/07/231521
import readline
import rlcompleter
import atexit
import os
# tab complete
readline.parse_and_bind('tab: complete')
# history file
histfile = os.path.join(os.environ['HOME'], '.python_history')
try:
    readline.read_history_file(histfile)
except IOError:
    pass
atexit.register(readline.write_history_file, histfile)
del os, histfile, readline, rlcompleter, atexit
