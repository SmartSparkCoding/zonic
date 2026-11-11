#!/usr/bin/env python3
"""Fills the Caddyfile template in from /etc/zonic/env and the stored password hash.

Kept out of install.sh because the substitution rules are the part worth reading, and
because a shell heredoc doing this is how you end up with a `$` eaten by the shell.

    render.py --template caddy/Caddyfile.template --env /etc/zonic/env \
              --hash /etc/zonic/password.hash --out /etc/zonic/Caddyfile
"""

import argparse
import sys


def read_env(path):
    values = {}
    try:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip()
    except OSError:
        pass
    return values


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--template", required=True)
    parser.add_argument("--env", required=True)
    parser.add_argument("--hash", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    values = read_env(args.env)
    domain = values.get("ZONIC_DOMAIN", "").strip()
    port = values.get("ZONIC_PUBLIC_PORT", "6769").strip() or "6769"

    if domain:
        # A hostname means Caddy does automatic HTTPS, which only works on the standard
        # ports: the certificate challenge arrives on 80 or 443 and nowhere else.
        site_address = domain
        auto_https = ""
    else:
        site_address = ":" + port
        auto_https = "auto_https off"

    try:
        with open(args.hash, encoding="utf-8") as handle:
            password_hash = handle.read().strip()
    except OSError:
        sys.exit("no password hash at %s, run install.sh" % args.hash)

    with open(args.template, encoding="utf-8") as handle:
        text = handle.read()

    for key, value in {
        "__SITE_ADDRESS__": site_address,
        "__AUTO_HTTPS__": auto_https,
        "__USER__": values.get("ZONIC_USER", "jacob"),
        "__HASH__": password_hash,
        "__GATE_PORT__": values.get("ZONIC_GATE_PORT", "8091"),
        "__STREAM_PORT__": values.get("ZONIC_STREAM_PORT", "8090"),
    }.items():
        text = text.replace(key, value)

    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write(text)

    scheme = "https" if domain else "http"
    host = domain if domain else "this box"
    print("wrote %s for %s://%s" % (args.out, scheme, host if domain else "%s:%s" % (host, port)))


if __name__ == "__main__":
    main()
