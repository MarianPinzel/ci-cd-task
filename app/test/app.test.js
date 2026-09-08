'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { handler, buildResponse } = require('../src/app');

test('buildResponse returns 200 with the given environment', () => {
  const res = buildResponse('dev');
  assert.equal(res.statusCode, 200);
  const body = JSON.parse(res.body);
  assert.equal(body.environment, 'dev');
});

test('handler resolves successfully', async () => {
  const res = await handler();
  assert.equal(res.statusCode, 200);
});
