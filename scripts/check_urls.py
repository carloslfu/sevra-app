"""Deterministic loopback fixtures, with no external source dependency."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json, subprocess, tempfile, threading
root=Path(__file__).resolve().parent.parent
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path=='/redirect':
            self.send_response(302);self.send_header('Location','/invoice.txt?token=private-fixture-token');self.end_headers();return
        if self.path=='/loop':
            self.send_response(302);self.send_header('Location','/loop');self.end_headers();return
        if self.path=='/auth':
            self.send_response(403);self.end_headers();return
        content=b'Synthetic brass invoice 1042'
        self.send_response(200);self.send_header('Content-Type','text/plain');self.send_header('Content-Length',str(len(content)));self.end_headers();self.wfile.write(content)
    def log_message(self,*args):pass
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='sevra-url-check-') as temporary:
        book=Path(temporary)/'URLs.sevra'
        def run(*args,success=True):
            r=subprocess.run([str(root/'output/bin/sevra'),*map(str,args)],capture_output=True,text=True)
            assert (r.returncode==0)==success,r.stdout+r.stderr
            return json.loads(r.stdout if success else r.stderr)
        run('create',book)
        base=f'http://127.0.0.1:{server.server_port}'
        captured=run('capture-url',book,base+'/redirect')['result']
        assert captured['assetID']
        assert run('search',book,'brass invoice')['result']['hits']
        run('capture-url',book,base+'/loop',success=False)
        run('capture-url',book,base+'/auth',success=False)
        run('capture-url',book,'file:///etc/passwd',success=False)
        # Query only synthetic metadata created by this test.
        import sqlite3
        database=sqlite3.connect(book/'workbook.sqlite')
        origins=database.execute('SELECT origin FROM assets').fetchall();database.close()
        assert len(origins)==1 and 'private-fixture-token' not in origins[0][0] and 'REDACTED' in origins[0][0]
        print(json.dumps({'redirectCaptured':True,'contentIndexed':True,'redirectLoopRefused':True,'accessFailureVisible':True,'nonHTTPRefused':True,'originCredentialRedacted':True}))
finally:
    server.shutdown();server.server_close()
