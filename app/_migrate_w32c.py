# W3-2: 菜单键位提示 + AlulaApp 透传
import io

# 1) workbench_page: _sc 助手 + 菜单标签动态化
p = 'lib/workbench/workbench_page.dart'
s = io.open(p, encoding='utf-8').read()

def rep(old, new):
    global s
    if old not in s:
        raise SystemExit('NOT FOUND: ' + old[:90])
    s = s.replace(old, new)

rep("""  /// 执行命令（键位/菜单/面板统一出口）；未知 id（用户键位指向不存在的命令）""",
"""  /// 菜单项的键位提示后缀（用户 keybindings.json 重绑定后自动跟随）。
  String _sc(String commandId) {
    final sc = _keybindings.shortcutFor(commandId);
    return sc == null ? '' : '    $sc';
  }

  /// 执行命令（键位/菜单/面板统一出口）；未知 id（用户键位指向不存在的命令）""")

rep("""                TitleMenuItem('打开文件夹', _showOpenFolderDialog),
                TitleMenuItem('保存    Ctrl+S', _saveActive),""",
"""                TitleMenuItem('打开文件夹', _showOpenFolderDialog),
                TitleMenuItem('保存${_sc('file.save')}', _saveActive),""")

rep("""                TitleMenuItem('命令面板    Ctrl+Shift+P', _showCommandPalette),
                TitleMenuItem('快速打开文件…    Ctrl+P', _showQuickOpen),""",
"""                TitleMenuItem(
                    '命令面板${_sc('view.commandPalette')}', _showCommandPalette),
                TitleMenuItem(
                    '快速打开文件…${_sc('view.quickOpen')}', _showQuickOpen),""")

io.open(p, 'w', encoding='utf-8', newline='\n').write(s)

# 2) main.dart: keybindingsStore 透传
p2 = 'lib/main.dart'
s2 = io.open(p2, encoding='utf-8').read()

rep("""import 'workbench/session_store.dart';""",
"""import 'workbench/keybindings.dart';
import 'workbench/session_store.dart';""")

rep("""    this.sessionStore,
    this.windowControls = false,
  });""",
"""    this.sessionStore,
    this.keybindingsStore,
    this.windowControls = false,
  });""")

rep("""  /// 会话 journal 注入点（测试用临时路径；默认真实用户目录）。
  final SessionStore? sessionStore;""",
"""  /// 会话 journal 注入点（测试用临时路径；默认真实用户目录）。
  final SessionStore? sessionStore;

  /// 键位覆盖文件注入点（测试用临时路径；默认真实用户目录）。
  final KeybindingsStore? keybindingsStore;""")

rep("""        sessionStore: sessionStore,
        windowControls: windowControls,""",
"""        sessionStore: sessionStore,
        keybindingsStore: keybindingsStore,
        windowControls: windowControls,""")

io.open(p2, 'w', encoding='utf-8', newline='\n').write(s2)
print('menu+pass-through ok')
