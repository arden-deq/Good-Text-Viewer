#!/usr/bin/env python3
"""Build the localized product pages from the app's public GitHub data."""

import argparse
from dataclasses import dataclass
from datetime import datetime
from html import escape
import json
from pathlib import Path
import re
import shutil
from string import Template
import tempfile
from urllib.request import Request, urlopen

SOURCE = Path(__file__).resolve().parent
SITE = "https://goodtextviewer.allmightdev.com"
REPO = "arden-deq/Good-Text-Viewer"
REPO_URL = f"https://github.com/{REPO}"
REPO_API = f"https://api.github.com/repos/{REPO}"
GITHUB_HEADERS = {"Accept": "application/vnd.github+json", "User-Agent": "GoodTextViewer-Site"}
RELEASE_URL = f"{REPO_URL}/releases"
PLATFORMS = {
    "macOS": ("macOS-universal", "mac_requirements", ("dmg", "zip")),
    "Windows": ("Windows-x64", "windows_requirements", ("exe", "zip")),
}

@dataclass(frozen=True)
class Build:
    url: str
    checksum: str
    size: str
    format: str


EN = {
    "headline": "Read TXT like a book.",
    "intro": "A fast, lightweight reader for text novels and long TXT files, with comfortable typography and a layout you can make your own.",
    "downloads": "Downloads",
    "download_title": "Download Good Text Viewer",
    "downloads_intro": "Choose a build for your computer or find a previous version in the archive. The app is free and open source.",
    "all_versions": "All versions",
    "archive_title": "Release archive",
    "navigation": "Main navigation",
    "star_label": "Star on GitHub",
    "star_count_label": "Star count",
    "starred": "Star saved on GitHub.",
    "star_cancelled": "GitHub authorization was cancelled.",
    "star_failed": "Could not confirm your star. Try again or visit the GitHub repository.",
    "mac_requirements": "macOS 13+ · Apple Silicon and Intel · Apple-notarized",
    "windows_requirements": "Windows x64 · Runs without installation",
    "no_build": "No downloadable build has been published for this platform yet.",
    "no_release_build": "Source release. No installer or app archive was published for this version.",
    "notes": "Release notes",
    "download": "Download",
    "reader_alt": "Good Text Viewer displaying The Harbor Lantern with the reading controls on the right",
    "spread_alt": "The Harbor Lantern laid out across two pages in Good Text Viewer",
    "preview_label": "Page layout preview",
    "one_page": "Single page",
    "two_pages": "Two pages",
    "features_label": "Reading features",
    "large_title": "Large files, quick start",
    "large_body": "Begin reading when the first page is ready. The rest of the document is paginated in the background.",
    "type_title": "Type that suits you",
    "type_body": "Choose a single page or a two-page spread. Adjust the font size and letter spacing for comfortable reading.",
    "wrap_title": "Clean up old line breaks",
    "wrap_body": "Let older fixed-width TXT paragraphs flow across the page. UTF-8, UTF-16, and legacy Korean CP949 are supported.",
    "spread_title": "Try the reading controls",
    "spread_body": "Change the sample’s font size and letter spacing. Open the full story in Good Text Viewer to try it in a two-page layout.",
    "demo_text": "The lantern at the end of the pier was still burning when Nora reached the harbor. She had expected the tide to be out by then, but dark water lapped at the steps and carried the smell of rain into the empty street.",
    "font_size": "Font size",
    "letter_spacing": "Letter spacing",
    "sample_link": "Open the sample story",
    "brew_title": "Install with Homebrew",
    "brew_body": "Get the macOS app from the DevDot tap.",
    "copy": "Copy",
    "copied": "Copied",
    "copy_error": "Copy failed. You can select and copy the command.",
}
KO = {
    "headline": "TXT 소설을 책처럼.",
    "intro": "긴 텍스트 소설도 편하게 읽을 수 있는 빠르고 가벼운 TXT 뷰어. 글자와 페이지 배치를 읽기 편하게 조절하세요.",
    "downloads": "다운로드",
    "download_title": "Good Text Viewer 다운로드",
    "downloads_intro": "내 컴퓨터에 맞는 파일을 받거나 이전 버전을 찾아보세요. 누구나 무료로 사용할 수 있는 오픈소스 앱입니다.",
    "all_versions": "모든 버전",
    "archive_title": "버전별 다운로드",
    "navigation": "주 메뉴",
    "star_label": "GitHub 스타",
    "star_count_label": "스타 수",
    "starred": "GitHub에 스타를 등록했어요.",
    "star_cancelled": "GitHub 권한 승인이 취소됐어요.",
    "star_failed": "스타 등록을 확인하지 못했어요. 다시 시도하거나 GitHub 저장소에서 등록해 주세요.",
    "mac_requirements": "macOS 13 이상 · Apple Silicon 및 Intel · Apple 공증",
    "windows_requirements": "Windows x64 · 무설치",
    "no_build": "이 운영체제용 다운로드 파일은 아직 공개되지 않았습니다.",
    "no_release_build": "이 버전은 소스 코드만 공개되어 있습니다.",
    "notes": "릴리스 노트",
    "download": "다운로드",
    "reader_alt": "Good Text Viewer에서 오른쪽 조절 패널과 함께 영문 소설을 한 쪽으로 펼친 화면",
    "spread_alt": "Good Text Viewer에서 영문 소설을 두 쪽으로 펼친 화면",
    "preview_label": "페이지 보기 미리보기",
    "one_page": "한 쪽",
    "two_pages": "두 쪽",
    "features_label": "읽기 기능",
    "large_title": "큰 파일도 빠르게",
    "large_body": "첫 페이지가 준비되면 바로 읽기 시작하세요. 나머지 페이지는 백그라운드에서 계산합니다.",
    "type_title": "읽기 편한 글자",
    "type_body": "한 쪽과 두 쪽 보기를 고르고, 글자 크기와 자간을 눈에 편하게 조절하세요.",
    "wrap_title": "오래된 줄바꿈 정리",
    "wrap_body": "고정 폭으로 저장된 TXT 문단을 페이지 너비에 맞춰 읽을 수 있습니다. UTF-8, UTF-16, CP949를 지원합니다.",
    "spread_title": "읽기 설정 체험",
    "spread_body": "예문으로 글자 크기와 자간을 조절해 보세요. 앱에서 샘플을 열면 두 쪽으로 펼쳐 읽을 수 있습니다.",
    "demo_text": "부두 끝의 등불은 노라가 항구에 도착했을 때도 여전히 타오르고 있었다. 그때쯤이면 물이 빠졌을 줄 알았지만, 검은 바닷물이 계단을 넘실대며 텅 빈 거리에 비 냄새를 실어 날랐다.",
    "font_size": "글자 크기",
    "letter_spacing": "자간",
    "sample_link": "샘플 소설 열기",
    "brew_title": "Homebrew로 설치",
    "brew_body": "DevDot의 tap에서 macOS 앱을 설치할 수 있습니다.",
    "copy": "복사",
    "copied": "복사됨",
    "copy_error": "복사에 실패했습니다. 명령어를 선택해 복사해 주세요.",
}


def github_releases():
    page = 1
    while True:
        url = f"{REPO_API}/releases?per_page=100&page={page}"
        request = Request(url, headers=GITHUB_HEADERS)
        with urlopen(request, timeout=15) as response:
            releases = json.load(response)
            has_next = 'rel="next"' in response.headers.get("Link", "")
        yield from releases
        if not has_next:
            return
        page += 1


def github_star_count():
    request = Request(REPO_API, headers=GITHUB_HEADERS)
    try:
        with urlopen(request, timeout=5) as response:
            repository = json.load(response)
    except (OSError, ValueError):
        return None

    count = repository.get("stargazers_count") if isinstance(repository, dict) else None
    return count if type(count) is int and count >= 0 else None


def catalog(raw_releases):
    releases = []
    for release in raw_releases:
        tag = release["tag_name"]
        if release["draft"] or release["prerelease"] or not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
            continue

        version = tag[1:]
        release_url = f"{RELEASE_URL}/tag/{tag}"
        assets = {asset["name"]: asset for asset in release["assets"] if asset["state"] == "uploaded"}
        builds = {}
        for platform, (suffix, _, formats) in PLATFORMS.items():
            for extension in formats:
                filename = f"Good-Text-Viewer-{version}-{suffix}.{extension}"
                asset = assets.get(filename)
                if asset:
                    url = f"{RELEASE_URL}/download/{tag}/{filename}"
                    checksum = url + ".sha256" if filename + ".sha256" in assets else ""
                    size = f"{asset['size'] / (1024 ** 2):.1f} MiB"
                    builds[platform] = Build(url, checksum, size, extension.upper())
                    break

        published = datetime.fromisoformat(release["published_at"].replace("Z", "+00:00")).date().isoformat()
        releases.append((version, published, release_url, builds))
    return sorted(releases, key=lambda release: tuple(map(int, release[0].split("."))), reverse=True)


def template(filename, **values):
    return Template((SOURCE / "templates" / filename).read_text(encoding="utf-8")).substitute(values)


def download_button(build, platform, text, version=""):
    label = f"{platform} {text['download']}" if text is KO else f"{text['download']} for {platform}"
    if version:
        label += f" · {version}"
    label += f" · {build.format}"
    return f'<a class="button" href="{build.url}"><span aria-hidden="true">↓</span>{escape(label)}</a>'


def platform_cards(releases, text):
    cards = []
    for platform, (_, requirements_key, _) in PLATFORMS.items():
        newest = next(((version, builds[platform]) for version, _, _, builds in releases if platform in builds), None)
        if newest:
            version, build = newest
            requirements = text[requirements_key]
            detail = f"<p>{escape(requirements)} · {build.size}</p>{download_button(build, platform, text, version)}"
        else:
            detail = f"<p>{escape(text['no_build'])}</p>"
        cards.append(f'<article class="platform-card"><h2>{platform}</h2>{detail}</article>')
    return "\n".join(cards)


def archive_rows(releases, text):
    rows = []
    for version, published, notes, builds in releases:
        if builds:
            links = []
            for platform, build in builds.items():
                label = f"{platform} {build.format}"
                verify = f'<a href="{build.checksum}" aria-label="SHA-256 · {platform} {version}">SHA-256</a>' if build.checksum else ""
                links.append(f'<li><a class="asset-download" href="{build.url}">{label}</a><span>{build.size}</span>{verify}</li>')
            files = "<ul>" + "".join(links) + "</ul>"
        else:
            files = f"<p>{escape(text['no_release_build'])}</p>"
        rows.append(
            f'<article class="release"><div><h3>{version}</h3><time datetime="{published}">{published}</time></div>'
            f'<div>{files}<a class="notes" href="{notes}">{escape(text["notes"])}</a></div></article>'
        )
    return "\n".join(rows)


def write_site(destination, releases, stars, github_star=False):
    shutil.copytree(SOURCE / "assets", destination / "assets", dirs_exist_ok=True)
    urls = []
    for lang, text in (("en", EN), ("ko", KO)):
        prefix = "/ko" if lang == "ko" else ""
        latest_mac = next((builds["macOS"] for _, _, _, builds in releases if "macOS" in builds), None)
        home = f"{prefix}/"
        downloads = f"{prefix}/downloads/"
        common = {key: escape(value) for key, value in text.items()}
        count_value = "" if stars is None else f"{stars:,}"
        hidden_count = " hidden" if stars is None else ""
        count_label = common["star_count_label"]
        star_content = (
            f'<span aria-hidden="true">☆</span> <span>{common["star_label"]}</span> '
            f'<span class="star-count"{hidden_count}><span class="sr-only">{count_label} </span>'
            f'<span data-star-count>{count_value}</span></span>'
        )
        for page in ("home", "downloads"):
            archive = page == "downloads"
            suffix = "/downloads/" if archive else "/"
            canonical = prefix + suffix
            title = text["download_title"] if archive else f"Good Text Viewer · {text['headline']}"
            if github_star:
                star_button = (
                    f'<form class="star-form" method="post" action="/star/start">'
                    f'<input type="hidden" name="page" value="{canonical}">'
                    f'<button class="github-star" type="submit">{star_content}</button></form>'
                )
                star_feedback = (
                    f'<p class="star-status" role="status" data-star-status data-starred="{common["starred"]}" '
                    f'data-cancelled="{common["star_cancelled"]}" data-failed="{common["star_failed"]}"></p>'
                )
            else:
                star_button = f'<a class="github-star" href="{REPO_URL}">{star_content}</a>'
                star_feedback = ""
            body = template(
                f"{page}.html",
                **common,
                primary_download=download_button(latest_mac, "macOS", text) if latest_mac else "",
                downloads_url=downloads,
                latest_platforms=platform_cards(releases, text) if archive else "",
                release_rows=archive_rows(releases, text) if archive else "",
            )
            output = destination / canonical.lstrip("/") / "index.html"
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(template(
                "page.html",
                **common,
                lang=lang,
                title=escape(title),
                description=escape(text["downloads_intro"] if archive else text["intro"]),
                canonical=canonical,
                english_url=SITE + suffix,
                korean_url=SITE + "/ko" + suffix,
                home_url=home,
                downloads_url=downloads,
                downloads_current=' aria-current="page"' if archive else "",
                repo_url=REPO_URL,
                star_button=star_button,
                star_feedback=star_feedback,
                alternate_lang="ko" if lang == "en" else "en",
                alternate_label="한국어" if lang == "en" else "English",
                alternate_url=("/ko" if lang == "en" else "") + suffix,
                body=body,
            ), encoding="utf-8")
            urls.append(f"<url><loc>{SITE}{canonical}</loc></url>")

    (destination / "robots.txt").write_text(f"User-agent: *\nSitemap: {SITE}/sitemap.xml\n", encoding="utf-8")
    (destination / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        + "\n".join(urls) + "\n</urlset>\n",
        encoding="utf-8",
    )


def publish(root, releases, stars, github_star=False):
    """Switch Nginx to a complete build, keeping the previous published build."""
    current = root / "current"
    previous = current.readlink() if current.is_symlink() else None
    build = Path(tempfile.mkdtemp(prefix="site-", dir=root))
    next_link = build.with_suffix(".link")
    try:
        write_site(build, releases, stars, github_star)
        build.chmod(0o755)
        next_link.symlink_to(build.name)
        next_link.replace(current)
    except Exception:
        next_link.unlink(missing_ok=True)
        shutil.rmtree(build)
        raise

    retained = {build.name}
    if previous:
        retained.add(previous.name)
    for old in root.glob("site-*"):
        if old.is_dir() and not old.is_symlink() and old.name not in retained:
            shutil.rmtree(old)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--publish", action="store_true", help="publish into an Nginx root with a current symlink")
    parser.add_argument("--github-star", action="store_true", help="enable the GitHub App star form")
    args = parser.parse_args()
    releases = catalog(github_releases())
    if not releases or not any(row[3] for row in releases):
        raise SystemExit("No public app packages found; keeping the current site.")

    stars = github_star_count()
    if args.publish:
        publish(args.destination, releases, stars, args.github_star)
    else:
        write_site(args.destination, releases, stars, args.github_star)


if __name__ == "__main__":
    main()
