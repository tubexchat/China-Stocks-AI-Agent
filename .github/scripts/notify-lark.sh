#!/usr/bin/env bash
# 向 Lark 群机器人推送构建/发布结果卡片。
#
# 环境变量:
#   LARK_WEBHOOK   机器人 webhook(必填)
#   STATUS         success | failure(决定颜色与标题前缀)
#   TITLE          标题正文,例如 "ChillSkill API 部署"
#   BODY           lark_md 正文(可多行,支持 **加粗**)
#   BUTTONS        可选,"文字|URL;文字|URL"
# 任何失败都不影响流水线结果(通知不该把构建搞红)。
set -u
[ -n "${LARK_WEBHOOK:-}" ] || { echo "LARK_WEBHOOK 未设置,跳过通知"; exit 0; }
python3 - <<'PY' || echo "Lark 通知发送失败(已忽略)"
import json, os, urllib.request
status = os.environ.get("STATUS", "success")   # success | warning | failure
ok = status == "success"
warn = status == "warning"
prefix = "✅ " if ok else ("⚠️ " if warn else "❌ ")
suffix = "成功" if ok else ("成功(有警告)" if warn else "失败")
title = prefix + os.environ.get("TITLE", "构建") + suffix
body = os.environ.get("BODY", "").replace("\\n", "\n")  # shell 里写的字面 \n → 真实换行
elements = [{"tag": "div", "text": {"tag": "lark_md", "content": body}}]
buttons = []
for item in filter(None, os.environ.get("BUTTONS", "").split(";")):
    if "|" in item:
        text, url = item.split("|", 1)
        buttons.append({"tag": "button", "text": {"tag": "plain_text", "content": text.strip()},
                        "type": "primary" if not buttons else "default", "url": url.strip()})
if buttons:
    elements.append({"tag": "action", "actions": buttons})
card = {"msg_type": "interactive", "card": {
    "config": {"wide_screen_mode": True},
    "header": {"template": "green" if ok else ("orange" if warn else "red"), "title": {"tag": "plain_text", "content": title}},
    "elements": elements}}
req = urllib.request.Request(os.environ["LARK_WEBHOOK"], data=json.dumps(card).encode(),
                             headers={"Content-Type": "application/json"})
print(urllib.request.urlopen(req, timeout=15).read().decode()[:200])
PY
exit 0
