#!/usr/bin/env python3
"""Check actual Release bundle contents against Ammutta's product rules, not just source files.

Ammutta is local-only, free and ships in English and Italian. These checks catch
regressions in the built product: transport exceptions, data-collection
declarations, missing localizations, missing icon or export-compliance metadata.
"""
from pathlib import Path
import plistlib
import sys

REQUIRED_LOCALIZATIONS = ("en", "it")


def verify(path):
    bundle = Path(path)
    info = plistlib.loads((bundle/'Info.plist').read_bytes())
    if 'NSAppTransportSecurity' in info:
        raise ValueError('A local-only app must not declare App Transport Security exceptions')
    if info.get('UIDeviceFamily') != [1]:
        raise ValueError(f"Ammutta targets iPhone only; actual UIDeviceFamily={info.get('UIDeviceFamily')!r}")
    icon = info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {})
    if icon.get('CFBundleIconName') != 'AppIcon' or not (bundle/'Assets.car').is_file():
        raise ValueError('Compiled AppIcon is missing from the actual application bundle')
    if info.get('ITSAppUsesNonExemptEncryption') is not False:
        raise ValueError('Set ITSAppUsesNonExemptEncryption to NO; Ammutta uses no non-exempt encryption')
    privacy = plistlib.loads((bundle/'PrivacyInfo.xcprivacy').read_bytes())
    if privacy.get('NSPrivacyTracking') is not False or privacy.get('NSPrivacyTrackingDomains', []) != []:
        raise ValueError('Privacy manifest must declare no tracking and no tracking domains')
    if privacy.get('NSPrivacyCollectedDataTypes', []) != []:
        raise ValueError('Privacy manifest must declare no collected data; Ammutta keeps all data on device')
    missing = [lang for lang in REQUIRED_LOCALIZATIONS if not (bundle/f'{lang}.lproj').is_dir()]
    if missing:
        raise ValueError(f"Compiled localizations are missing: {', '.join(missing)}")
    if not info.get('CFBundleShortVersionString') or not info.get('CFBundleVersion'):
        raise ValueError('Version/build metadata is missing')
    return True


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: verify-ios-bundle.py PATH/Ammutta.app')
    verify(sys.argv[1])
    print('Release bundle has compiled icon, en/it localizations, iPhone metadata, '
          'no transport exceptions, no declared data collection and export-compliance metadata')
