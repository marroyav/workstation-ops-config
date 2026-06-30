#!/usr/bin/env python3
import argparse
import json
import mimetypes
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


API_ROOT = "https://api.github.com"
API_VERSION = "2022-11-28"


class GitHubError(RuntimeError):
    pass


def read_token(args: argparse.Namespace) -> str:
    for env_name in ("DAPHNE_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN", "GITHUB_PAT"):
        value = os.environ.get(env_name, "").strip()
        if value:
            return value

    token_file = Path(args.token_file).expanduser()
    if token_file.is_file():
        value = token_file.read_text(encoding="utf-8").strip()
        if value:
            return value

    raise GitHubError(
        "missing GitHub token; set DAPHNE_GITHUB_TOKEN (or GH_TOKEN/GITHUB_TOKEN) "
        f"or create {token_file}"
    )


def api_request(
    token: str,
    method: str,
    url: str,
    *,
    json_body=None,
    raw_body=None,
    headers=None,
):
    request_headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": API_VERSION,
        "User-Agent": "daphne-build-ops/1.0",
    }
    if headers:
        request_headers.update(headers)

    body = None
    if json_body is not None:
        body = json.dumps(json_body).encode("utf-8")
        request_headers["Content-Type"] = "application/json"
    elif raw_body is not None:
        body = raw_body

    request = urllib.request.Request(url, data=body, headers=request_headers, method=method)
    try:
        with urllib.request.urlopen(request) as response:
            response_body = response.read()
            if not response_body:
                return None
            content_type = response.headers.get("Content-Type", "")
            if "application/json" in content_type:
                return json.loads(response_body.decode("utf-8"))
            return response_body
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise GitHubError(f"{method} {url} failed with HTTP {exc.code}: {detail}") from exc


def ensure_release(token: str, repo: str, tag: str, name: str):
    url = f"{API_ROOT}/repos/{repo}/releases/tags/{urllib.parse.quote(tag, safe='')}"
    try:
        return api_request(token, "GET", url)
    except GitHubError as exc:
        if "HTTP 404" not in str(exc):
            raise

    create_url = f"{API_ROOT}/repos/{repo}/releases"
    return api_request(
        token,
        "POST",
        create_url,
        json_body={
            "tag_name": tag,
            "name": name,
            "prerelease": True,
            "draft": False,
            "generate_release_notes": False,
        },
    )


def upload_release_asset(token: str, release: dict, zip_path: Path):
    asset_name = zip_path.name
    existing_asset = None
    for asset in release.get("assets", []):
        if asset.get("name") == asset_name:
            existing_asset = asset
            break

    if existing_asset is not None:
        api_request(token, "DELETE", existing_asset["url"])

    upload_url = release["upload_url"].split("{", 1)[0]
    query = urllib.parse.urlencode({"name": asset_name})
    content_type = mimetypes.guess_type(asset_name)[0] or "application/zip"
    return api_request(
        token,
        "POST",
        f"{upload_url}?{query}",
        raw_body=zip_path.read_bytes(),
        headers={"Content-Type": content_type},
    )


def commit_comment_body(asset_name: str, download_url: str, commit_sha: str, zip_path: Path):
    marker = f"<!-- daphne-build-artifact:{asset_name} -->"
    return "\n".join(
        [
            f"Automated build artifact for `{commit_sha[:7]}`.",
            "",
            f"- Overlay zip: [{asset_name}]({download_url})",
            f"- Local source: `{zip_path}`",
            "",
            marker,
        ]
    )


def upsert_commit_comment(token: str, repo: str, commit_sha: str, body: str, asset_name: str):
    list_url = f"{API_ROOT}/repos/{repo}/commits/{urllib.parse.quote(commit_sha, safe='')}/comments"
    comments = api_request(token, "GET", list_url) or []
    marker = f"<!-- daphne-build-artifact:{asset_name} -->"

    for comment in comments:
        if marker in comment.get("body", ""):
            update_url = f"{API_ROOT}/repos/{repo}/comments/{comment['id']}"
            updated = api_request(token, "PATCH", update_url, json_body={"body": body})
            return updated["html_url"]

    create_url = f"{API_ROOT}/repos/{repo}/commits/{urllib.parse.quote(commit_sha, safe='')}/comments"
    created = api_request(token, "POST", create_url, json_body={"body": body})
    return created["html_url"]


def parse_args():
    parser = argparse.ArgumentParser(description="Upload a build zip to GitHub and upsert a commit comment.")
    parser.add_argument("--repo", required=True, help="owner/repo")
    parser.add_argument("--commit", required=True, help="full or short commit sha")
    parser.add_argument("--zip", dest="zip_path", required=True, help="path to overlay zip")
    parser.add_argument(
        "--token-file",
        default="~/.config/daphne-build-ops/github-token",
        help="path to a file containing a GitHub token",
    )
    parser.add_argument(
        "--release-tag",
        default="daphne-build-artifacts",
        help="release tag used to store uploaded build zips",
    )
    parser.add_argument(
        "--release-name",
        default="DAPHNE Build Artifacts",
        help="release name used when creating the artifact bucket release",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    zip_path = Path(args.zip_path).expanduser().resolve()
    if not zip_path.is_file():
        raise GitHubError(f"zip file not found: {zip_path}")

    token = read_token(args)
    release = ensure_release(token, args.repo, args.release_tag, args.release_name)
    uploaded_asset = upload_release_asset(token, release, zip_path)
    download_url = uploaded_asset["browser_download_url"]
    comment_body = commit_comment_body(zip_path.name, download_url, args.commit, zip_path)
    comment_url = upsert_commit_comment(token, args.repo, args.commit, comment_body, zip_path.name)

    result = {
        "zip": str(zip_path),
        "asset_name": zip_path.name,
        "download_url": download_url,
        "comment_url": comment_url,
        "commit": args.commit,
        "repo": args.repo,
        "release_tag": args.release_tag,
    }
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except GitHubError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(2)
