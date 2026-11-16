"""Package only native source/configuration and synthetic test resources for transfer to a Mac."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parent
output = root.parent / 'FamilyHealth-iPhone-source.zip'
allowed = {'.swift', '.plist', '.entitlements', '.pbxproj', '.xcscheme', '.json', '.py', '.sh', '.mjs', '.md'}
excluded = {'build', 'DerivedData', 'xcuserdata', '__pycache__', '.git'}
files = [path for path in root.rglob('*') if path.is_file() and path.suffix in allowed and not excluded.intersection(path.relative_to(root).parts)]
with ZipFile(output, 'w', compression=ZIP_DEFLATED) as archive:
    for path in sorted(files):
        archive.write(path, Path('FamilyHealth-iPhone/ios') / path.relative_to(root))
    archive.writestr('FamilyHealth-iPhone/START-HERE.md', '''# 家和 iPhone 原生工程

在 Mac/Xcode 打开 ios/FamilyHealth.xcodeproj，详细步骤见 ios/README.md。

需要运行现有家和 FastAPI 后端，并在 App 登录页填写它的可达服务根地址。此包仅包含 SwiftUI 原生客户端、工程、合成测试资料和检查脚本。

当前状态：Windows 源码语法解析、工程结构和接口集成检查通过；Xcode 编译、模拟器运行、iPhone 签名和 HealthKit 真机验收仍需执行。此包不是 IPA。
''')
print(f'Packaged {len(files)} native files: {output.name} ({output.stat().st_size:,} bytes)')
