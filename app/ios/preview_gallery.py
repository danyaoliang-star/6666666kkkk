"""Create a local gallery from genuine Xcode test image attachments, never draw UI mocks."""
import argparse
import json
from html import escape
from pathlib import Path
from urllib.parse import quote

LABELS = {
    '01-native-login': '登录', '02-native-chat': '小康对话', '03-native-health': '健康总览',
    '04-native-plans': '生活计划', '05-native-account': '我的', '06-native-health-permissions': '健康授权',
    '07-native-reports': '病历夹', '08-native-care': '目标与复查',
}


def collect_labels(value, result):
    if isinstance(value, dict):
        filename = value.get('exportedFileName')
        name = value.get('suggestedHumanReadableName') or value.get('name') or ''
        if filename and name:
            result[Path(filename).name] = name
        for child in value.values():
            collect_labels(child, result)
    elif isinstance(value, list):
        for child in value:
            collect_labels(child, result)


def gallery(folder):
    folder = folder.resolve()
    names = {}
    for manifest in folder.rglob('*.json'):
        collect_labels(json.loads(manifest.read_text(encoding='utf-8')), names)
    images = list(folder.rglob('*.png')) + list(folder.rglob('*.jpg')) + list(folder.rglob('*.jpeg'))
    if not images:
        raise SystemExit('Xcode did not export any native screenshots. Inspect the diagnostics artifact.')
    cards = []
    seen = set()
    for image in sorted(images, key=lambda path: names.get(path.name, path.name)):
        name = names.get(image.name, image.stem)
        key = next((key for key in LABELS if key in name), None)
        if key:
            seen.add(key)
        title = LABELS.get(key, name)
        relative = quote(image.relative_to(folder).as_posix())
        cards.append(f'<figure><img src="{relative}" alt="{escape(title)}的原生模拟器渲染截图" loading="lazy"><figcaption>{escape(title)}</figcaption></figure>')
    page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>家和 · iPhone 原生预览</title>
<style>body{font-family:system-ui,sans-serif;margin:0;padding:28px;background:#f3f2fa;color:#211943}h1{font-size:24px}p{color:#746d88;line-height:1.8;max-width:850px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(270px,1fr));gap:24px}figure{margin:0}img{display:block;width:100%;height:auto;border-radius:22px;background:white;box-shadow:0 8px 35px #21194312}figcaption{text-align:center;margin:12px;font-weight:600}</style>
<h1>家和 · iPhone 原生预览</h1><p>这些图片由 Xcode 在 iOS 模拟器中运行真实 SwiftUI 页面后导出。画面使用合成测试资料；没有读取个人健康记录，也不代表已完成 iPhone 签名或真机验收。此页面仅展示已导出的截图，不能操作 App。</p><main>'''
    (folder / 'index.html').write_text(page + '\n'.join(cards) + '</main></html>', encoding='utf-8')
    print(f'Created native screenshot gallery: {len(images)} images, {len(seen)} named preview screens.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('folder', type=Path)
    gallery(parser.parse_args().folder)
