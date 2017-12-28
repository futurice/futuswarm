#!/usr/bin/env python
from __future__ import print_function
from flask import Flask, request
import requests
app = Flask(__name__)

@app.route("/")
def hello():
    return "OK"

def url_status(url):
    try:
        return requests.get(url, timeout=0.5).status_code
    except Exception as e:
        return 500

@app.route("/check")
def check():
    service = request.args.get("service", "localhost")
    port = request.args.get("port", 8000)
    full_url = "http://{}:{}".format(service, port)
    rs = map(lambda i: url_status(full_url), range(1,20,1))
    rs_uniq = "".join(map(str, list(set(rs))))
    return "{}".format(rs_uniq)

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8000, debug=False)
