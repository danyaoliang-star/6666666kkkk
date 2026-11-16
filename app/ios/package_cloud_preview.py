"""Prepare the minimal, reviewable source payload for a dedicated GitHub preview repository."""
import json
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parent
workspace = root.parent.parent
output = root.parent / 'FamilyHealth-GitHub-preview.zip'
allowed = {'.swift', '.plist', '.entitlements', '.pbxproj', '.xcscheme', '.json', '.py', '.sh', '.mjs', '.md'}
excluded = {'build', 'DerivedData', 'xcuserdata', '__pycache__', '.git'}
files = [path for path in root.rglob('*') if path.is_file() and path.suffix in allowed and not excluded.intersection(path.relative_to(root).parts)]
files.append(workspace / '.github/workflows/ios-native.yml')
manifest = []
with ZipFile(output, 'w', compression=ZIP_DEFLATED) as archive:
    for path in sorted(files):
        relative = path.relative_to(workspace).as_posix()
        assert relative.startswith('app/ios/') or relative == '.github/workflows/ios-native.yml'
        archive.write(path, relative)
        manifest.append({'path': relative, 'bytes': path.stat().st_size})
    archive.writestr('README.md', '# 家和 iPhone 原生预览\n\nSwiftUI 原生工程与合成测试资料。查看 app/ios/CLOUD-PREVIEW.md 了解云端预览流程。\n\nGitHub Actions 工作流：iPhone native preview。此仓库用于生成真实 iOS 模拟器界面截图，尚未完成真机签名与安装。\n')
    archive.writestr('.gitignore', 'app/ios/build/\napp/ios/DerivedData/\n**/xcuserdata/\n*.xcuserstate\n__pycache__/\n')
    archive.writestr('PREVIEW-SOURCE-MANIFEST.json', json.dumps(manifest, ensure_ascii=False, indent=2))
with ZipFile(output) as archive:
    assert archive.testzip() is None
print(f'Cloud preview payload: {len(manifest)} whitelisted source files; {output.name}, {output.stat().st_size:,} bytes')
