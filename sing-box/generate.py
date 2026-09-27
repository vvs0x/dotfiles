#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Builds the sing-box config from the subscription plus the CyberGhost profiles.

The provider serves native sing-box JSON, so its nodes are used verbatim; only
the routing around them is ours. Re-run this to pick up subscription changes:

    uv run ~/.config/sing-box/generate.py

or, since the shebang hands it to uv, just:

    ~/.config/sing-box/generate.py
"""

import json
import re
import ssl
import sys
import urllib.request
from pathlib import Path

BASE = Path.home() / ".config/sing-box"
SUBSCRIPTION_URL_FILE = BASE / "subscription.url"
SUBSCRIPTION_CACHE = BASE / "subscription.json"
OUTPUT = BASE / "config.json"

OVPN_DIR = BASE / "vpn"
# One certificate set for the whole account, plus a plain list of countries.
DEVICE_DIR = OVPN_DIR / "device"
COUNTRIES_FILE = OVPN_DIR / "countries.txt"

# CyberGhost's server names are formulaic: the prefix picks the protocol, the
# two-letter code picks the country. 87-1-* is UDP, which this network blocks,
# so everything runs over TCP - same ciphers, just a different transport.
VPN_SERVER_TEMPLATE = "97-1-{code}.cg-dialup.net"
VPN_SERVER_PORT = 443
VPN_NETWORK = "tcp"

# Providers ship fake "nodes" that only display quota or notices.
PSEUDO_NODE_MARKERS = (
    "剩余流量", "套餐到期", "客户端设置", "官网", "订阅", "过期", "到期", "群", "防失联",
)
GROUP_TYPES = {"selector", "urltest", "direct", "block", "dns"}

CLASH_API_PORT = 9090
TUN_ADDRESS = ["172.19.0.1/30"]
# The country picker.
VPN_GROUP = "VPN"
# Marks the copies dialled through whatever the VPN group currently points at.
# Written in travel order - VPN first, then the node - so the dashboard label
# matches what actually happens on the wire.
CHAIN_PREFIX = "vpn ⇢ "
CHAIN_GROUP = "vpn ⇢ auto"
# The one switch that decides where traffic leaves the machine. Named for its
# role, not for one of the things it can point at.
EXIT_GROUP = "EXIT"
USER_AGENT = "sing-box/1.14.1"
DASHBOARD_URL = "https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"


def fetch_subscription(refresh=True):
    """Download the subscription, falling back to the cached copy."""
    if refresh and SUBSCRIPTION_URL_FILE.exists():
        url = SUBSCRIPTION_URL_FILE.read_text().strip()
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=30, context=ssl.create_default_context()) as response:
                raw = response.read().decode("utf-8")
            json.loads(raw)  # reject anything that is not the sing-box format
            SUBSCRIPTION_CACHE.write_text(raw)
            SUBSCRIPTION_CACHE.chmod(0o600)
            print("  subscription   : refreshed")
        except Exception as exc:
            if not SUBSCRIPTION_CACHE.exists():
                raise SystemExit(f"Subscription download failed and no cache exists: {exc}")
            print(f"  subscription   : download failed ({type(exc).__name__}), using cache")

    if not SUBSCRIPTION_CACHE.exists():
        raise SystemExit(f"No subscription. Put its URL into {SUBSCRIPTION_URL_FILE}")

    return json.loads(SUBSCRIPTION_CACHE.read_text())


def is_pseudo_node(tag):
    return any(marker in tag for marker in PSEUDO_NODE_MARKERS)


def extract_nodes(subscription):
    """Keep the real proxy outbounds; groups and quota placeholders go away."""
    nodes, skipped = [], []
    for outbound in subscription.get("outbounds") or []:
        if outbound.get("type") in GROUP_TYPES:
            continue
        tag = outbound.get("tag", "")
        if is_pseudo_node(tag):
            skipped.append(tag)
            continue
        nodes.append(outbound)
    return nodes, skipped


def read_device():
    """The one certificate/credential set that identifies this CyberGhost device.

    Verified: the client certificate authenticates the *device*, not a country -
    the same set connects to any cg-dialup server. So one device slot covers
    every country, and the account's device limit stops being a constraint.
    """
    missing = [
        name
        for name in ("ca.crt", "client.crt", "client.key", "device.txt")
        if not (DEVICE_DIR / name).is_file()
    ]
    if missing:
        raise SystemExit(
            f"Incomplete device in {DEVICE_DIR}: missing {', '.join(missing)}.\n"
            "Download one OpenVPN TCP configuration from CyberGhost (any country) "
            "and put its ca.crt, client.crt and client.key there, plus the username "
            "and password as the two lines of device.txt."
        )

    lines = [
        line.strip()
        for line in (DEVICE_DIR / "device.txt").read_text().splitlines()
        if line.strip()
    ]
    if len(lines) < 2:
        raise SystemExit(
            f"{DEVICE_DIR / 'device.txt'} needs the username on the first line "
            "and the password on the second."
        )

    return lines[0], lines[1]


def read_countries():
    """Parse countries.txt: '<iso code> = <display name>', one per line."""
    if not COUNTRIES_FILE.is_file():
        raise SystemExit(f"No country list. Create {COUNTRIES_FILE}, e.g. 'de = Germany'.")

    countries, malformed = [], []
    for raw in COUNTRIES_FILE.read_text().splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue

        code, _, name = line.partition("=")
        code = code.strip().lower()
        if not re.fullmatch(r"[a-z]{2}", code):
            malformed.append(raw.strip())
            continue

        countries.append((code, name.strip() or code.upper()))

    return countries, malformed


def build_vpn_endpoints():
    """One endpoint per country, all sharing the single device certificate."""
    username, password = read_device()
    countries, malformed = read_countries()

    certificates = {
        "certificate_path": str(DEVICE_DIR / "ca.crt"),
        "client_certificate_path": str(DEVICE_DIR / "client.crt"),
        "client_key_path": str(DEVICE_DIR / "client.key"),
    }

    endpoints = []
    for code, name in countries:
        endpoints.append({
            "type": "openvpn-client",
            "tag": name,
            "mode": "tls",
            "server": VPN_SERVER_TEMPLATE.format(code=code),
            "server_port": VPN_SERVER_PORT,
            "network": VPN_NETWORK,
            "username": username,
            "password": password,
            "tls": dict(certificates),
            "data_ciphers": ["AES-256-GCM", "AES-128-GCM", "AES-256-CBC"],
            "auth": "SHA256",
            # Headroom for QUIC inside the tunnel; 1500 leaves hysteria2 fragmenting.
            "mtu": 1400,
        })

    return endpoints, malformed


def chain_via_vpn(nodes):
    """Copy every node so it is dialled *through* the selected VPN country.

    detour points at the VPN group rather than one endpoint, so the chain
    follows whatever is picked there. The resolver is pinned to dns-direct:
    the node hostname must be looked up outside the tunnel, otherwise the
    lookup itself has to traverse the chain it is trying to build.
    """
    chained = []
    for node in nodes:
        copy = dict(node)
        copy["tag"] = CHAIN_PREFIX + node["tag"]
        copy["detour"] = VPN_GROUP
        copy["domain_resolver"] = "dns-direct"
        chained.append(copy)
    return chained


def build_config(nodes, vpn_endpoints):
    node_tags = [n["tag"] for n in nodes]
    vpn_tags = [e["tag"] for e in vpn_endpoints]

    # Every connection flows through this one selector, so switching it in the
    # dashboard redirects the whole machine: direct, a proxy node, or the VPN.
    selector = {
        "type": "selector",
        "tag": EXIT_GROUP,
        "outbounds": ["direct", "auto"] + ([VPN_GROUP, CHAIN_GROUP] if vpn_tags else []) + node_tags,
        "default": "direct",
        "interrupt_exist_connections": False,
    }
    urltest = {
        "type": "urltest",
        "tag": "auto",
        "outbounds": node_tags,
        "url": "https://www.gstatic.com/generate_204",
        "interval": "5m",
        "tolerance": 50,
    }
    # Own group so the countries stay together instead of padding the main list.
    # "direct" sits in here too: picking it drops the VPN leg out of the chain,
    # which turns "VPN -> auto" back into a plain proxy hop without touching EXIT.
    vpn_group = {
        "type": "selector",
        "tag": VPN_GROUP,
        "outbounds": vpn_tags + ["direct"],
        "interrupt_exist_connections": False,
    }
    # Chain: selected VPN country -> fastest proxy node -> internet.
    chained = chain_via_vpn(nodes) if vpn_tags else []
    vpn_plus_auto = {
        "type": "urltest",
        "tag": CHAIN_GROUP,
        "outbounds": [n["tag"] for n in chained],
        "url": "https://www.gstatic.com/generate_204",
        "interval": "10m",
        "tolerance": 100,
    }
    groups = [selector, urltest]
    if vpn_tags:
        groups += [vpn_group, vpn_plus_auto]

    config = {
        "log": {
            "level": "warn",
            "timestamp": True,
            "output": "/opt/homebrew/var/log/sing-box.log",
        },
        "experimental": {
            "clash_api": {
                "external_controller": f"127.0.0.1:{CLASH_API_PORT}",
                # Web UI at http://127.0.0.1:9090/ui, fetched once on first start.
                "external_ui": "ui",
                "external_ui_download_url": DASHBOARD_URL,
                "external_ui_download_detour": "direct",
                "default_mode": "rule",
            },
            "cache_file": {"enabled": True, "store_fakeip": True},
        },
        "dns": {
            "servers": [
                # Follows the selector, so DNS never leaks past the chosen exit.
                {"type": "https", "tag": "dns-proxy", "server": "1.1.1.1", "detour": EXIT_GROUP},
                # Resolves the proxy/VPN hostnames themselves via the OS resolver,
                # which sing-box reaches outside its own tunnel.
                {"type": "local", "tag": "dns-direct"},
            ],
            "rules": [{"clash_mode": "direct", "server": "dns-direct"}],
            "final": "dns-proxy",
            "strategy": "ipv4_only",
        },
        "inbounds": [
            {
                "type": "tun",
                "tag": "tun-in",
                "address": TUN_ADDRESS,
                "mtu": 9000,
                "auto_route": True,
                "stack": "gvisor",
            }
        ],
        "outbounds": [*groups, *nodes, *chained, {"type": "direct", "tag": "direct"}],
        "route": {
            "rules": [
                {"action": "sniff"},
                {"protocol": "dns", "action": "hijack-dns"},
                # LAN stays reachable in every mode - router, printers, NAS.
                {"ip_is_private": True, "outbound": "direct"},
                {"clash_mode": "direct", "outbound": "direct"},
                {"clash_mode": "global", "outbound": EXIT_GROUP},
            ],
            "final": EXIT_GROUP,
            "auto_detect_interface": True,
            # 1.14 wants an explicit resolver for outbounds addressed by domain.
            "default_domain_resolver": {"server": "dns-direct"},
        },
    }

    if vpn_endpoints:
        config["endpoints"] = vpn_endpoints

    return config


def main():
    refresh = "--offline" not in sys.argv
    subscription = fetch_subscription(refresh=refresh)
    nodes, skipped = extract_nodes(subscription)
    if not nodes:
        raise SystemExit("The subscription contained no usable nodes.")

    vpn_endpoints, malformed = build_vpn_endpoints()
    config = build_config(nodes, vpn_endpoints)

    OUTPUT.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n")
    OUTPUT.chmod(0o600)

    print(f"  wrote          : {OUTPUT}")
    print(f"  proxy nodes    : {len(nodes)}")
    print(f"  vpn countries  : {len(vpn_endpoints)} over {VPN_NETWORK} "
          f"({', '.join(e['tag'] for e in vpn_endpoints)})")
    if malformed:
        print(f"  bad country    : {', '.join(malformed)} (expected '<iso code> = <name>')")
    if skipped:
        print(f"  placeholders   : {len(skipped)} skipped")


if __name__ == "__main__":
    main()
