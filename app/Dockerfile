FROM node:22-alpine AS build
WORKDIR /app

COPY package.json ./
COPY src/ ./src/

FROM gcr.io/distroless/nodejs22-debian13
WORKDIR /app

COPY --from=build /app/package.json ./
COPY --from=build /app/src ./src

EXPOSE 8080
CMD ["src/server.js"]
