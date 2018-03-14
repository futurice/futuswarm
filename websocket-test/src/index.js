"use strict";
const express = require("express");
const http = require("http");
const WebSocket = require("ws");
const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });
wss.on('connection', (ws) => {
    ws.send('OK');
});
server.listen(process.env.PORT || 8000, () => {
    console.log(`Server online on port ${server.address().port}`);
});
