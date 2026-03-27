#!/usr/bin/env python3

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def github_request(url: str, token: str) -> dict:
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def anonymous_token_status(chart_name: str) -> int:
    url = (
        "https://ghcr.io/token?"
        + urllib.parse.urlencode(
            {
                "scope": f"repository:joejulian/charts/{chart_name}:pull",
                "service": "ghcr.io",
            }
        )
    )
    req = urllib.request.Request(url)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status
    except urllib.error.HTTPError as exc:
        return exc.code


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("chart_name")
    parser.add_argument("--token", required=True)
    parser.add_argument("--retries", type=int, default=30)
    parser.add_argument("--sleep", type=int, default=10)
    args = parser.parse_args()

    package_name = urllib.parse.quote(f"charts/{args.chart_name}", safe="")
    package_url = f"https://api.github.com/user/packages/container/{package_name}"

    for attempt in range(1, args.retries + 1):
        try:
            package = github_request(package_url, args.token)
        except urllib.error.HTTPError as exc:
            status = exc.code
            body = exc.read().decode()
            print(
                f"Package lookup failed for charts/{args.chart_name} "
                f"(attempt {attempt}/{args.retries}): HTTP {status}: {body}",
                file=sys.stderr,
            )
            if attempt == args.retries:
                return 1
            time.sleep(args.sleep)
            continue

        visibility = package.get("visibility")
        repo_full_name = (package.get("repository") or {}).get("full_name")
        token_status = anonymous_token_status(args.chart_name)

        if visibility == "public" and repo_full_name == "joejulian/charts" and token_status == 200:
            print(
                f"Verified charts/{args.chart_name} is public, linked to "
                f"{repo_full_name}, and anonymously readable."
            )
            return 0

        print(
            f"charts/{args.chart_name} not ready yet "
            f"(attempt {attempt}/{args.retries}): "
            f"visibility={visibility!r} repo={repo_full_name!r} "
            f"anonymous_token_status={token_status}",
            file=sys.stderr,
        )
        if attempt == args.retries:
            return 1
        time.sleep(args.sleep)

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
