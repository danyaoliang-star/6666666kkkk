"""Structural checks runnable on Windows; Xcode remains the authoritative compiler."""
import json
import plistlib
import re
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(__file__).resolve().parent
project = (root / 'FamilyHealth.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
source_files = list((root / 'FamilyHealth').glob('*.swift'))
test_files = list((root / 'FamilyHealthTests').glob('*.swift'))
for source in source_files + test_files:
    assert f'path = "{source.name}";' in project, f'Missing Xcode reference: {source.name}'
    text = source.read_text(encoding='utf-8')
    assert 'import WebKit' not in text and 'WKWebView' not in text, f'Unexpected web UI in native source: {source.name}'
assert sum('@main' in p.read_text(encoding='utf-8') for p in source_files) == 1
definitions = re.findall(r'^    ([0-9A-F]{24}) = ', project, re.MULTILINE)
assert len(definitions) == len(set(definitions)), 'Duplicate Xcode object IDs'
references = set(re.findall(r'\b[0-9A-F]{24}\b', project))
assert references == set(definitions), 'Unresolved Xcode object IDs'
for name in ['Info.plist', 'Info-Debug.plist', 'FamilyHealth.entitlements']:
    plistlib.loads((root / 'FamilyHealth' / name).read_bytes())
release = plistlib.loads((root / 'FamilyHealth/Info.plist').read_bytes())
debug = plistlib.loads((root / 'FamilyHealth/Info-Debug.plist').read_bytes())
assert not release['NSAppTransportSecurity'].get('NSAllowsArbitraryLoads', False)
assert debug['NSAppTransportSecurity'].get('NSAllowsArbitraryLoads', False)
assert 'NSAllowsArbitraryLoadsInWebContent' not in debug['NSAppTransportSecurity']
assert plistlib.loads((root / 'FamilyHealth/FamilyHealth.entitlements').read_bytes())['com.apple.developer.healthkit']
scheme = ET.parse(root / 'FamilyHealth.xcodeproj/xcshareddata/xcschemes/FamilyHealth.xcscheme')
assert scheme.find('.//TestableReference/BuildableReference').attrib['BlueprintName'] == 'FamilyHealthTests'
fixtures = json.loads((root / 'FamilyHealthTests/native-contract.json').read_text(encoding='utf-8'))
assert len(fixtures) == 20
assert fixtures['member']['relation'] == '本人'
assert fixtures['health']['consent_id'] == 'synthetic-fixture-consent-not-valid-on-server'
assert fixtures['care']['goals'][0]['latest']['value'] == 3.8
print(f'Native project structure valid: {len(source_files)} app files, {len(test_files)} test files, {len(fixtures)} synthetic fixtures; no web-view UI.')
