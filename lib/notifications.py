#!/usr/bin/env python
import web
import sys

notifications = {key: {'booting':'completed'} for key in sys.argv[2:] }

urls = (
    '/show', 'show',
    '/register/(?P<machine>.+)/(?P<task>.+)/(?P<status>.+)', 'register',
    '/status/(?P<machine>.+)/(?P<task>.+)', 'status'
)

class show:
    def GET(self):
        output = ''
        for k, v in notifications.items():
            d = ' '.join(['[ %s | %s ]' % (key, value) for (key, value) in v.items()])
            output += '{0:>20}: {1}\n'.format(k, d)
        return output

class register:
    def GET(self, machine, task, status):
        d = notifications.get(machine)
        if d is None:
            return 'Unknown machine %s' % machine
        d[t] = s

class status:
    def GET(self, machine, task):
        d = notifications.get(machine)
        if d is None:
            return 'Unknown machine %s' % machine
        s = d.get(task)
        if s is None:
            return 'Unknown task %s for %s' % (task,machine)
        else:
            return s

if __name__ == "__main__":
    web.config.debug = False
    app = web.application(urls, globals())
    app.run()
