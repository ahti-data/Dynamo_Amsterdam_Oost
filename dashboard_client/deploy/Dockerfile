# Bouwt en serveert de monitor als zelfstandige container.
# Gebruik (vanuit de projectroot):
#   docker build -f deploy/Dockerfile -t dynamo-monitor .
#   docker run -d --restart unless-stopped -p 8080:80 dynamo-monitor
# Vereist dat data-prep/build_data.py al is gedraaid (dashboard/public/data gevuld).
#
# Toegangsbeveiliging zit IN de app: de data wordt versleuteld en de browser vraagt
# om een wachtwoord (zie deploy/encrypt_data.py). Wil je die encryptie ook in de
# container? Versleutel dan na de build-stap /app/dist/data, bv. door in de build-stage
# `RUN python deploy/encrypt_data.py "$WACHTWOORD" /app/dist/data` toe te voegen met een
# build-ARG. Let op: een build-ARG belandt in de image-history — voor een echt geheim
# wachtwoord is de statische-upload-route (build → encrypt → dist/ uploaden) schoner.

FROM node:22-alpine AS build
WORKDIR /app
COPY dashboard/package.json dashboard/package-lock.json* ./
RUN npm install
COPY dashboard/ ./
RUN npm run build

FROM nginx:alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK CMD wget -qO- http://localhost/healthz || exit 1
