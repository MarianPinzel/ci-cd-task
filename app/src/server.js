'use strict';

const http = require('node:http');
const { buildResponse } = require('./app');

const port = process.env.PORT || 8080;

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok' }));
    return;
  }

  const { statusCode, headers, body } = buildResponse(process.env.APP_ENV || 'unknown');
  res.writeHead(statusCode, headers);
  res.end(body);
});

server.listen(port, () => {
  console.log(`listening on ${port}`);
});
