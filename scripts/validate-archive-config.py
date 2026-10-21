#!/usr/bin/env python3
"""Validate non-secret archive configuration. Emits only static, hand-written diagnostics."""
import os
import re

# Placeholder prefix used by ios/project.yml for local development builds.
PLACEHOLDER_BUNDLE_PREFIX = 'dev.ammutta.'


def validate_archive(env):
    if not re.fullmatch(r'[A-Z0-9]{10}', env.get('AMMUTTA_TEAM_ID', '')):
        raise ValueError('Set AMMUTTA_TEAM_ID to your ten-character Apple Developer team ID')
    bundle = env.get('AMMUTTA_BUNDLE_ID', '')
    if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', bundle) or bundle.startswith(PLACEHOLDER_BUNDLE_PREFIX):
        raise ValueError('Set AMMUTTA_BUNDLE_ID to your own registered reverse-DNS bundle identifier')
    if not re.fullmatch(r'[1-9][0-9]*', env.get('AMMUTTA_BUILD_NUMBER', '')):
        raise ValueError('Set AMMUTTA_BUILD_NUMBER to a new positive integer for each upload')


if __name__ == '__main__':
    try:
        validate_archive(os.environ)
    except ValueError as error:
        raise SystemExit(str(error)) from error
    print('Archive configuration is valid (no credentials required)')
