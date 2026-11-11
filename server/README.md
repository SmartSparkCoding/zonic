# The Zonic web session

Amazon Music in a browser that lives on your server, streamed to whatever machine you are
sitting at. One password, a settings page at `/settings`, and a session that shuts itself
down a few minutes after you leave.

This is not a web app that reimplements Amazon Music. It is a real Google Chrome inside a
container, and you are looking at its screen:

```
browser  ──websocket──►  Caddy :8080  ──►  Selkies :8090  ──►  Chrome  ──►  music.amazon.com
         password,          loopback         container
         settings, wake
```

## Why it has to be a real browser

Two dead ends worth knowing before you read the rest, because both are the obvious design:

- **You cannot iframe `music.amazon.com`.** Amazon sends framing headers, and stripping
  them with a proxy does not help: the page is scoped to its own origin, so its cookies,
  storage and service worker all break, and the Widevine licence is bound to that origin
  anyway.
- **You cannot use Chromium.** Protected audio needs a Widevine CDM, and the open-source
  builds do not ship one. The Selkies desktop image installs **Google Chrome**, which does,
  and that is the whole reason this works.

So the server runs a browser and streams pixels and audio, and your laptop is a viewer.

## What you need

- A Debian box with Docker and Docker Compose v2. On Nest that means your LXC container.
- A port to reach it on, and either Nest's reverse proxy or a tunnel to put a hostname in
  front of it.
- About 1.5 GB of RAM free while a session is running.

Nest gives you 2 vCPU and 2 GB. That is enough for one viewer at 720p with the settings in
`docker-compose.yml`; it is not enough for two, and it will not do a GPU-quality stream.
Caddy, the settings app and the timer together use around 40 MB.

## Install

```bash
sudo apt install -y docker.io docker-compose-v2
git clone https://github.com/SmartSparkCoding/zonic /opt/zonic
sudo /opt/zonic/server/host/install.sh
```

The installer:

1. copies `.env.example` to `.env` and makes `data/chrome` and `data/state`;
2. asks for a password and stores only its bcrypt hash, in `/etc/zonic/password.hash`;
3. downloads Caddy if it is not already at `/usr/local/bin/caddy`;
4. renders `/etc/caddy/Caddyfile` from `caddy/Caddyfile.template`;
5. installs and starts `caddy.service`, `zonic-gate.service` and `zonic-idle.timer`.

Run it again after a `git pull`; it rewrites the units and the config and keeps your
password and Chrome profile.

Then point your hostname at port **8080**. On Nest, that is the port you give their reverse
proxy, either the `*.username.hackclub.app` one or `client.zonic.navaratne.uk`.

## Using it

- `https://your.host/` is the session. First visit starts the container and shows a page
  that reloads itself until Chrome is up, about ten to fifteen seconds.
- `https://your.host/settings` is status, the idle timeout, and Start/Stop.
- Sign in to Amazon Music once, with **Keep me signed in** ticked. The Chrome profile is a
  volume, so that survives restarts of the container and of the server.
- Close the tab and the session stops itself after the idle timeout. Nothing keeps running.

## How the idle shutdown works

Selkies runs a shell command when the last client disconnects and another when the first one
connects, so the session drops or removes a single marker file in `data/state`. A systemd
timer checks that file once a minute and stops the container when it has been sitting there
longer than your timeout.

That is more reliable than counting sockets or watching traffic, both of which get confused
by an idle tab that is still connected. The tradeoff is that an open tab counts as "in use"
even if you walked away, so the session stays up while the page is open.

## Security

- The stream listens on `127.0.0.1:8090` only. Caddy is the only way in.
- Caddy puts HTTP basic auth in front of everything, including `/settings` and the wake
  page. Put it behind HTTPS: a tunnel, or Nest's proxy, or your own certificate with
  `auto_https` back on.
- Basic auth is a password over the wire, so plain `http://` on a public port is a bad
  idea. If you are not going through a tunnel, terminate TLS in Caddy instead.
- The session holds a live Amazon login. Treat the box like you would a laptop that is
  signed in.
- One thing to know: an unauthenticated request to a stopped session reaches the wake page,
  because Caddy answers the 5xx before auth runs on that path. It can start your container,
  it cannot see the stream.

## Limits

- **Video quality.** Software encoding on 2 vCPU. 720p30 at 2.5 Mbps is what fits; the
  sidebar has the rest of the controls. Scrolling a heavy page will look soft.
- **Audio** goes over the same websocket. Expect roughly 2 to 6 Mbps while listening.
- **Nest may not have Docker.** Their LXC containers usually allow it, but if `docker
  compose up` fails on a permission or `iptables` error, that is why, and the fix is on
  their side.
- **Amazon may not like a datacenter IP.** Sign-in from a server sometimes gets a
  challenge. Once you are through it, the profile keeps you in.
- Nothing here has been run against a live Amazon account yet. Chrome, the image and the
  stream settings are from Selkies' own documentation; the compose file, the autostart
  entry, the idle marker and the settings app are checked as far as you can check them
  without a browser in the loop.

## Files

| File | What it does |
| --- | --- |
| `docker-compose.yml` | the session container, its limits, its volumes |
| `.env.example` | ports, idle minutes, memory caps |
| `session/start-chrome.sh` | opens Amazon Music as a chromeless Chrome window |
| `session/amazon-music.desktop` | the LXQt autostart entry that runs it |
| `caddy/Caddyfile.template` | password, routing, streaming, wake-on-5xx |
| `caddy/caddy.service` | Caddy as a service |
| `gate/gate.py` | status, start, stop, the settings page |
| `host/zonic-idle.sh` | stops the session once nobody is connected |
| `host/zonic-idle.{service,timer}` | runs the above every minute |
| `host/zonic-gate.service` | the settings app as a service |
| `host/install.sh` | all of the above, idempotently |

## When it goes wrong

```bash
docker compose -f /opt/zonic/server/docker-compose.yml logs -f session   # Chrome and Selkies
journalctl -u zonic-gate -f                                              # the settings app
journalctl -u caddy -f                                                   # the front door
systemctl list-timers zonic-idle.timer                                   # is the reaper alive
cat /var/lib/zonic/idle.log                                              # when it stopped, and why
```

Black screen with the controls visible means Chrome did not start: check the session log for
`start-chrome.sh`. Video but no sound means audio is off in the sidebar's audio panel.
