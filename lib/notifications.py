#!/usr/bin/env python
import web
import sys

print sys.argv[2:]
notifications = {key: {} for key in sys.argv[2:] }

urls = (
    '/', 'status',
    '/progress', 'progress',
    '/fail/(?P<machine>.+)', 'fail',
    '/(?P<machine>.+)/(?P<task>.+)', 'task'
)

class status:
    def GET(self):
        output = ''
        for k, v in notifications.items():
            d = ' '.join(['[ %s | %s ]' % (key, value) for (key, value) in v.items()])
            output += '{0:>20}: {1}\n'.format(k, d)
        return output

class task:
    def GET(self, machine, task):
        d = notifications.get(machine)
        if d is None:
            sys.stderr.write('[ERROR: %s | %s ] Unknown machine\n' % (machine,task))
            return 'ERR'
        s = d.get(task)
        if s is None:
            sys.stderr.write('[ERROR: %s | %s ] Unknown task\n' % (machine,task))
            return 'ERR'
        else:
            return s

    def POST(self, machine, task):
        status = web.data()
        d = notifications.get(machine)
        if d is None:
            sys.stderr.write('[ERROR: %s | %s ] Unknown machine\n' % (machine,task))
            return 'ERR'
        d[task] = status
        return '[ %s | %s ] registered for %s' % (task, status, machine)

class fail:
    def GET(self, machine):
        d = notifications.get(machine)
        if d is None:
            sys.stderr.write('[ERROR: %s ] Unknown machine\n' % machine)
            return 'ERR'
        return d.get('fail')

    def POST(self, machine):
        d = notifications.get(machine)
        if d is None:
            sys.stderr.write('[ERROR: %s | %s ] Unknown machine\n' % (machine,task))
            return 'ERR'
        for k in d.iterkeys():
            if k is not 'progress':
                d[k] = 'FAIL'
        d['fail'] = 'FAIL'
        return '[ %s ] failure registered' % machine

class progress:
    def GET(self):
        return '|' + ' '.join(['{0} {1}|'.format(k, v.get("progress",'.?.')) for k, v in notifications.items()])

if __name__ == "__main__":
    web.config.debug = False
    app = web.application(urls, globals())
    app.run()
