#!/usr/bin/env python3
import os
import re
import sys
import html
import requests
import json

CHANNEL_URL = 'https://t.me/flclashx'
SUPPORT_URL = 'https://t.me/tribute/app?startapp=dtyh'

BOLD = re.compile(r'\*\*(.+?)\*\*')
CODE = re.compile(r'`([^`]+)`')
BULLET = re.compile(r'^[-*•]\s+')

def link_buttons(view_url):
    """One row of URL buttons under the post, in place of links in its text."""
    return {
        'inline_keyboard': [[
            {'text': '👀 Посмотреть', 'url': view_url, 'style': 'primary'},
            {'text': '❤️ Поддержать', 'url': SUPPORT_URL, 'style': 'success'},
        ]]
    }

def send_telegram_message(bot_token, chat_id, message, buttons, parse_mode='HTML'):
    """Send a message to a Telegram chat."""
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"

    payload = {
        'chat_id': chat_id,
        'text': message,
        'parse_mode': parse_mode,
        'reply_markup': buttons,
    }

    try:
        response = requests.post(url, json=payload, timeout=30)
        response.raise_for_status()
        return True
    except requests.exceptions.RequestException as e:
        # Don't log sensitive data in error messages
        print(f"Error sending message to channel: {e}")
        return False

def format_changes(changes):
    """Turn the release notes' Markdown bullets into Telegram HTML."""
    lines = []
    for line in changes.splitlines():
        line = BULLET.sub('', line.strip())
        if not line:
            continue
        text = ''.join(
            f'<code>{html.escape(part, quote=False)}</code>'
            if index % 2
            else BOLD.sub(r'<b>\1</b>', html.escape(part, quote=False))
            for index, part in enumerate(CODE.split(line))
        )
        lines.append(f'• {text}')
    return '\n'.join(lines)

def format_release_message(version, commits, is_stable):
    """Format the release notification message (HTML parse mode).

    Commit subjects contain Markdown-hostile characters (e.g. `_` in
    "file_picker", `startForeground`), which broke the legacy Markdown parser
    with a 400 "can't parse entities". HTML only needs &<> escaped, so escape
    every dynamic part and use HTML tags for formatting.
    """
    version_clean = html.escape(version.lstrip('v'))

    emoji = "🎉" if is_stable else "🚀"
    release_type = "FlClashX. Stable Version on GitHub" if is_stable else "FlClashX. PreRelease Version on GitHub"

    message = f"{emoji} <b>{version_clean} in GitHub!</b> {emoji}\n\n"
    message += f"<i>{release_type}</i>\n\n"
    changes = format_changes(commits or '')
    if changes:
        message += "<b>What's new:</b>\n"
        message += changes

    return message.rstrip()

def main():
    bot_token = os.environ.get('TELEGRAM_BOT_TOKEN')
    channel_id_1 = os.environ.get('TELEGRAM_CHANNEL_ID_1')
    channel_id_2 = os.environ.get('TELEGRAM_CHANNEL_ID_2')
    channel_id_3 = os.environ.get('TELEGRAM_CHANNEL_ID_3')
    version = os.environ.get('VERSION')
    commits = os.environ.get('COMMITS')
    release_url = os.environ.get('RELEASE_URL')
    is_stable = os.environ.get('IS_STABLE', 'false').lower() == 'true'

    if not all([bot_token, channel_id_1, channel_id_2, channel_id_3, version, release_url]):
        print("Error: Missing required environment variables")
        print(f"TELEGRAM_BOT_TOKEN: {'✓' if bot_token else '✗'}")
        print(f"TELEGRAM_CHANNEL_ID_1: {'✓' if channel_id_1 else '✗'}")
        print(f"TELEGRAM_CHANNEL_ID_2: {'✓' if channel_id_2 else '✗'}")
        print(f"TELEGRAM_CHANNEL_ID_3: {'✓' if channel_id_3 else '✗'}")
        print(f"VERSION: {'✓' if version else '✗'}")
        print(f"RELEASE_URL: {'✓' if release_url else '✗'}")
        sys.exit(1)
    
    # Full release message for channels 1 and 2
    message = format_release_message(version, commits, is_stable)
    buttons = link_buttons(release_url)
    
    # Simple notification message for channel 3
    version_clean = html.escape(version.lstrip('v'))
    simple_message = f"Новый релиз!❤️\nFlClashX {version_clean}"
    simple_buttons = link_buttons(CHANNEL_URL)
    
    # Log notification details (without secrets)
    print(f"Sending notification for version {version}...")
    print(f"Release URL: {release_url}")
    print(f"Release type: {'Stable' if is_stable else 'Pre-release'}")
    print(f"\nFull message preview (first 200 chars):\n{'-'*50}\n{message[:200]}...\n{'-'*50}\n")
    
    success_count = 0
    total_channels = 3
    
    print(f"Sending full message to channel 1...")
    if send_telegram_message(bot_token, channel_id_1, message, buttons):
        print("✓ Channel 1: Success")
        success_count += 1
    else:
        print("✗ Channel 1: Failed")
    
    print(f"Sending full message to channel 2...")
    if send_telegram_message(bot_token, channel_id_2, message, buttons):
        print("✓ Channel 2: Success")
        success_count += 1
    else:
        print("✗ Channel 2: Failed")
    
    print(f"Sending simple message to channel 3...")
    if send_telegram_message(bot_token, channel_id_3, simple_message, simple_buttons):
        print("✓ Channel 3: Success")
        success_count += 1
    else:
        print("✗ Channel 3: Failed")
    
    print(f"\nSent to {success_count}/{total_channels} channels")
    
    if success_count < total_channels:
        sys.exit(1)
    
    print("All notifications sent successfully!")

if __name__ == '__main__':
    main()
