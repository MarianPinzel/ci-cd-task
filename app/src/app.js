'use strict';

function buildResponse(env) {
  return {
    statusCode: 200,
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      message: 'hello from ci-cd-task demo app',
      environment: env,
      version: process.env.APP_VERSION || 'dev',
    }),
  };
}

exports.handler = async () => buildResponse(process.env.APP_ENV || 'unknown');
exports.buildResponse = buildResponse;
