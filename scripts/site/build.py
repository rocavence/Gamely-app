#!/usr/bin/env python3
"""產生官網：docs/index.html（中文，手寫的原始檔）→ docs/<語言>/index.html（英、日、韓、西、葡）。

用法：python3 scripts/site/build.py
- 中文改 docs/index.html；其他語言改 scripts/site/<語言>.json，key 對應頁面上的 data-i（內文）、
  data-i-content（meta content）、data-i-href（連結）
- 版本號從 project.yml 的 MARKETING_VERSION 帶入（<span class="ver"> 與 JSON-LD softwareVersion）
- FAQ 的 JSON-LD 由頁面上的 FAQ（data-i="faq.qN" / "faq.aN"）產生，兩頁各自一份
- sitemap.xml 的 lastmod 更新成今天
"""

from __future__ import annotations

import datetime
import html
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs"
ZH = DOCS / "index.html"
HERE = Path(__file__).parent
# 翻譯檔 → (<html lang>, 網址路徑)
LANGS = {"en": ("en", "en"), "ja": ("ja", "ja"), "ko": ("ko", "ko"), "es": ("es", "es"), "pt": ("pt-BR", "pt")}


def inner(s: str, opening: re.Match) -> tuple[int, int]:
    """從開頭標籤算出元素內文的範圍（處理同名標籤巢狀）。"""
    tag, depth, pos = opening.group(1), 1, opening.end()
    pattern = re.compile(rf"<(/?){tag}\b[^>]*>")
    while depth:
        t = pattern.search(s, pos)
        if not t:
            sys.exit(f"找不到 {opening.group(0)} 的結尾 </{tag}>")
        depth += -1 if t.group(1) else 1
        pos = t.end()
    return opening.end(), t.start()


def openings(s: str, key: str = r"[^\"]+") -> list[re.Match]:
    return list(re.finditer(rf'<(\w+)\b[^>]*\sdata-i="({key})"[^>]*>', s))


def element_span(s: str, key: str) -> tuple[int, int]:
    return inner(s, openings(s, re.escape(key))[0])


def keys(s: str, attr: str) -> list[str]:
    return re.findall(rf'\s{attr}="([^"]+)"', s)


def set_version(s: str, version: str) -> str:
    s = re.sub(r'<span class="ver">[^<]*</span>', f'<span class="ver">{version}</span>', s)
    return re.sub(r'"softwareVersion": "[^"]*"', f'"softwareVersion": "{version}"', s)


def text(fragment: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", "", fragment)).strip()


def set_faq_ld(s: str) -> str:
    pairs, i = [], 1
    while f'data-i="faq.q{i}"' in s:
        q, a = (text(s[slice(*element_span(s, f"faq.{x}{i}"))]) for x in "qa")
        pairs.append({"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}})
        i += 1
    ld = json.dumps({"@context": "https://schema.org", "@type": "FAQPage", "mainEntity": pairs},
                    ensure_ascii=False, indent=2)
    out, n = re.subn(r'(<script type="application/ld\+json" id="ld-faq">\n)[\s\S]*?(\n</script>)',
                     lambda m: m.group(1) + ld + m.group(2), s)
    assert n == 1, "找不到 ld-faq"
    return out


def translate(s: str, en: dict[str, str], code: str, lang: str, path: str) -> str:
    used = set(keys(s, "data-i")) | set(keys(s, "data-i-content")) | set(keys(s, "data-i-href"))
    if missing := sorted(used - en.keys()):
        sys.exit(f"{code}.json 缺少：{', '.join(missing)}")
    if unused := sorted(en.keys() - used):
        print(f"{code}.json 沒用到：{', '.join(unused)}")
    for m in reversed(openings(s)):  # 從後往前換，前面的位置才不會跑掉
        a, b = inner(s, m)
        s = s[:a] + en[m.group(2)] + s[b:]
    for attr, target in (("data-i-content", "content"), ("data-i-href", "href")):
        s = re.sub(rf'(\s{attr}="([^"]+)"\s{target}=")[^"]*"',
                   lambda m: m.group(1) + html.escape(en[m.group(2)], quote=True) + '"', s)
    s = s.replace('<html lang="zh-Hant">', f'<html lang="{lang}">', 1)
    s = s.replace('data-lang="zh" class="on"', 'data-lang="zh"').replace(f'data-lang="{code}">', f'data-lang="{code}" class="on">')
    s = s.replace('"url": "https://gamely.rocavence.com/"', f'"url": "https://gamely.rocavence.com/{path}/"')
    return s.replace("<head>", "<head>\n<!-- 由 scripts/site/build.py 產生，不要手改 -->", 1)


def write_sitemap(today: str) -> None:
    """每種語言一個網址，各自列出全部語言版本；外加 llms.txt。"""
    site = "https://gamely.rocavence.com"
    pages = [("zh-Hant", "/")] + [(lang, f"/{path}/") for lang, path in LANGS.values()]
    alternates = "\n".join(f'    <xhtml:link rel="alternate" hreflang="{lang}" href="{site}{url}"/>' for lang, url in pages)
    alternates += f'\n    <xhtml:link rel="alternate" hreflang="x-default" href="{site}/en/"/>'
    urls = "".join(f"  <url>\n    <loc>{site}{url}</loc>\n    <lastmod>{today}</lastmod>\n{alternates}\n  </url>\n" for _, url in pages)
    urls += f"  <url>\n    <loc>{site}/llms.txt</loc>\n    <lastmod>{today}</lastmod>\n  </url>\n"
    (DOCS / "sitemap.xml").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"\n'
                                      f'        xmlns:xhtml="http://www.w3.org/1999/xhtml">\n{urls}</urlset>\n')


def main() -> None:
    version = re.search(r'MARKETING_VERSION: "([^"]+)"', (ROOT / "project.yml").read_text()).group(1)
    zh = set_faq_ld(set_version(ZH.read_text(), version))
    ZH.write_text(zh)

    for code, (lang, path) in LANGS.items():
        strings = json.loads((HERE / f"{code}.json").read_text())
        out = DOCS / path / "index.html"
        out.parent.mkdir(exist_ok=True)
        out.write_text(set_faq_ld(set_version(translate(zh, strings, code, lang, path), version)))

    write_sitemap(datetime.date.today().isoformat())
    print(f"官網已產生：v{version}，docs/index.html + " + "、".join(f"docs/{p}/" for _, p in LANGS.values()))


if __name__ == "__main__":
    main()
