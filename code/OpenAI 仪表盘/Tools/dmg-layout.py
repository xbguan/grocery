#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""为 DMG 生成 .DS_Store（窗口尺寸、背景图、图标位置）。

用法: dmg-layout.py <挂载点> <App名.app>

依赖内嵌在 Tools/pylib（ds_store + mac_alias，均为纯 Python），
不需要 pip 安装任何东西，也不碰系统 Python 环境。

为什么手写 .DS_Store 而不是用 AppleScript 调 Finder：
在当前环境下 osascript 操作 Finder 一律返回 -10004（自动化权限未授予），
create-dmg 之类的工具同样走 AppleScript，所以都不可用。
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pylib"))

import mac_alias                                    # noqa: E402
from ds_store import DSStore                        # noqa: E402

VOL = sys.argv[1]
APP = sys.argv[2]

BG_REL = ".background/bg.png"
BG_ABS = os.path.join(VOL, BG_REL)

if not os.path.isdir(os.path.join(VOL, APP)):
    sys.exit("找不到 App: %s" % os.path.join(VOL, APP))
if not os.path.isfile(BG_ABS):
    sys.exit("找不到背景图: %s" % BG_ABS)

# 图标位置（Finder 坐标系，原点在窗口左上角）
APP_POS = (168, 200)
APPS_POS = (492, 200)
WIN_BOUNDS = "{{200, 180}, {660, 420}}"

# 背景图必须用 alias 引用：记录卷名 + 相对路径，
# DMG 卷名固定，所以在别的机器上挂载后也能解析到。
alias_bytes = mac_alias.Alias.for_file(BG_ABS).to_bytes()

ds_path = os.path.join(VOL, ".DS_Store")
if os.path.exists(ds_path):
    os.remove(ds_path)
open(ds_path, "wb").close()

with DSStore.open(ds_path, "w+") as d:
    # 窗口外观
    d["."]["bwsp"] = {
        "WindowBounds": WIN_BOUNDS,
        "ShowSidebar": False,
        "ShowStatusBar": False,
        "ShowTabView": False,
        "ShowToolbar": False,
        "ShowPathbar": False,
        "ContainerShowSidebar": False,
        "PreviewPaneVisibility": False,
        "SidebarWidth": 0,
        "ShowIconPreview": True,
        "ViewStyle": "icnv",
    }

    # 图标视图设置
    d["."]["icvp"] = {
        "viewOptionsVersion": 1,
        "iconSize": 128.0,
        "textSize": 12.0,
        "labelOnBottom": True,
        "showItemInfo": False,
        "showIconPreview": True,
        "arrangeBy": "none",
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "scrollPositionX": 0.0,
        "scrollPositionY": 0.0,
        "backgroundColorRed": 1.0,
        "backgroundColorGreen": 1.0,
        "backgroundColorBlue": 1.0,
        "backgroundType": 2,          # 2 = 使用背景图
        "backgroundImageAlias": alias_bytes,
    }

    # 卷设置版本，Finder 会用它判断结构是否受支持
    d["."]["vSrn"] = ("long", 1)

    # 条目位置
    d[APP]["Iloc"] = APP_POS
    d["Applications"]["Iloc"] = APPS_POS

print("已写入 .DS_Store: %s" % ds_path)
