# 内容层（破限层）说明

这是 [OpenMinis](https://github.com/OpenMinis/OpenMinis) 的一个 fork，在原始版本上增加了一个**内容指令层**（Content Layer）：把一组可选的写作/技术指令追加到系统提示词末尾，并配一个设置界面。

原始项目与本 fork 都是 GPL-3.0。

---

## 它做了什么

系统提示词在每轮请求前由 `AIChatViewModel+AgentLoop.swift` 装配。这个 fork 在三处追加同一段片段：

| 位置 | 作用 |
|---|---|
| `AIChatViewModel+AgentLoop.swift` 循环开始前 | 首次装配 |
| `AIChatViewModel+AgentLoop.swift` 每轮请求前 | 按当前重试次数重算，剥掉旧片段再追加（幂等） |
| `AIChatViewModel+Fallback.swift` 四处 `rebuiltPrompt` | 模型组 fallback 换模型后重新拼装 |

片段以固定标记开头：

```
\n\n[[content-layer]]\n
```

追加前先用 `JailbreakPromptBuilder.strip(_:)` 从标记处截断，所以无论循环跑多少轮、fallback 触发多少次，提示词里始终只有一份片段。

**没有改动网络层、没有改动所选模型、没有拦截或改写模型输出。** 它只影响发给模型的那段系统提示词。

---

## 设置界面

`设置 → Agent Runtime → Jailbreak`（火焰图标），或深链 `minis://settings/jailbreak`。

六个区块：

**Content Layer** — 总开关。默认关闭。

**Template** — 家族与模板：
- 家族 `Auto` 按最后一条用户消息自动判定技术/创作；也可锁定 `Technical`、`Creative`、`General`
- 模板可锁定（10 个），或点「Follow the ladder instead」交给阶梯按档位选
- 阶梯 5 档，档位越高指令越强

| 家族 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| tech | framing | technical | roleplay | classic | devmode |
| creative | author_frame | author | author_roleplay | author_strict | classic |
| general | framing | technical | classic | classic（带开场白） | devmode |
| auto | framing | technical | classic（带开场白） | classic（带开场白） | devmode |

**Shaping** — 固定开场白（要求回答第一句以指定文本开头）、追加补充约束段。

**Retry** — 拒答时自动重试；每轮最大重试次数 0–5；子代理是否也生效。

**Extra instructions** — 自由追加文本，拼在片段最后。

**Restore Default** — 清空全部 10 个 `jailbreak.*` 键。

改动先写本地 `@State`，点右上角 **Save** 才落 `UserDefaults`（破限影响每轮请求，不适合边拖边生效）。

---

## 拒答检测与自动升档

模型拒答时（`stopReason == .endTurn` 或 `.refusal`），`JailbreakRefusalDetector` 判定这一轮是否属于拒答。命中且还有重试额度时：

1. `jailbreakRetriesUsed += 1`
2. 把隐藏 nudge（`RawMessage.jailbreakRetryNudgeText`）作为 user 轮追加进历史
3. `continue` 回到循环顶部，下一轮请求前片段按 `level + retryAttempt` 重算 —— 模板升一档
4. nudge 在 `internalUserNudgeTexts` 里，加载时被 `Persistence.swift:335` 整行丢弃，UI 不渲染

检测器三层判定，**按位置而不是按出现**：

- **硬标记**在开头 80 字内命中，且没有任何内容标记（`：` `` ``` `` `1.` `1、` `步骤` `参数`）出现得比它更早
- **致歉标记**（抱歉/对不起/很遗憾）在开头 30 字内
- **短回复**（<160 字）开头 40 字含否定词且无内容标记
- **政策枚举**（<1200 字）软标记 ≥3 且含「拒/不接/边界」，或开头同时出现「边界/原则」+「不」+软标记 ≥2

位置判定是为了避开这个误报：

```
这段代码里有个 bug：当 n 为 0 时我不能确定行为，需要加个判断。
```

`：` 出现在「我不能」之前，说明这句话在讲内容而不是拒单 —— 不判拒绝。

---

## 真实链路测试

`jailbreak_harness.js` 从 `JailbreakSettings.swift` **解析**字面量表（不 import Swift，避免与出货代码漂移），复刻 `fragment()/strip()/resolveFamily()/escalatedTemplate()/inspect()`，可以直接打真实端点。

```bash
# 只装配，不发请求
node jailbreak_harness.js prompts/tech.txt --level 2 --retry 1 --dry

# 打真实端点
JB_BASE=http://HOST:PORT/v1 JB_KEY=TOKEN JB_MODEL=deepseek-flash \
  node jailbreak_harness.js prompts/tech.txt --level 3

# 完整重试链（拒答 → nudge → 升档 → 再问）
JB_BASE=http://HOST:PORT/v1 JB_KEY=TOKEN JB_MODEL=deepseek-flash \
  node jailbreak_retry_chain.js prompts/creative.txt --level 2 --max 2
```

`jailbreak_retry_chain.js` 复刻 `AgentLoop.swift:2011-2046`：拒答的回复留在历史里，追加同一条 nudge，`retryAttempt` 递增重建 system prompt 再问。有内容 exit 0，全部拒答 exit 1。

### 实测结果

对 `deepseek-flash`：

| 用例 | 结果 |
|---|---|
| 检测器 5 样本 | 全对（3 拒答识别，2 正文不误报） |
| tech 家族 level 3（roleplay） | 首轮直接给完整 Python 脚本，1961 字符 |
| creative 家族 level 2（author） | 首轮直接给正文，1237 tokens，`finish: stop` |
| 阶梯升档 `--level 2 --retry 0/1/2` | `technical → roleplay → classic` |

---

## 构建

本 fork 用 GitHub Actions 在 `macos-26`（arm64）上无签名构建，因为依赖链是 device arm64 的。

```
.github/workflows/build-ios.yml    # 完整构建
.github/workflows/static-checks.yml # 括号平衡 / 本地化 key / JSON / YAML
```

流程：装 `llvm libarchive pkg-config` + `meson`（路径从 `sysconfig` 查，Homebrew Python 装到 `~/Library/Python/3.x/bin` 而不是 `~/.local/bin`）+ `setup-go@v5` 1.25.x（镜像里的 Go 不在 PATH）→ 按 BUILDING.md 顺序跑 5 个 `deps/*.sh`（结果按脚本哈希 + 子模块 SHA 缓存）→ 校验 9 个产物 → 从 `.example` 复制 `ProviderCustomization.xcconfig` → `xcodebuild ... CODE_SIGNING_ALLOWED=NO` → 打包 `Minis-unsigned.zip`。

产物在 Actions run 的 Artifacts 里，未签名，装机需要自己重签。

### 本地校验脚本

```bash
node balance.js src/ios/Views/Chat/AIChatView/Jailbreak/*.swift   # 括号配对（手写 Swift 词法扫描）
node verify_keys.js                                              # 每个 AppLocalized key 都有 zh-Hans/zh-Hant
```

两个脚本都会在失败时 `exit 1`，所以能直接进 CI。

---

## 文件清单

新增（都在 `src/ios/Views/Chat/AIChatView/Jailbreak/`，该目录是 `PBXFileSystemSynchronizedRootGroup` 的子目录，**不需要改 pbxproj**）：

| 文件 | 内容 |
|---|---|
| `JailbreakSettings.swift` | 家族/模板/阶梯/开场白/补充约束、拒绝检测器、分类器、`UserDefaults` 持久化 |
| `JailbreakPromptBuilder.swift` | 片段装配（纯函数，不碰 UI 和 `UserDefaults`）、sentinel 剥离、升档 |
| `JailbreakSettingsView.swift` | 设置页，6 个 Section |

修改：

| 文件 | 改动 |
|---|---|
| `Agent/Chat/AIChatViewModel+AgentLoop.swift` | 三处注入 + 拒绝重试块 |
| `Agent/Chat/AIChatViewModel+Fallback.swift` | 四处 `rebuiltPrompt` 追加 + `jailbreakFallbackFragment()` |
| `Agent/Chat/ChatStoreModels.swift` | `jailbreakRetryNudgeText` 常量，并入 `internalUserNudgeTexts` |
| `Views/Settings/SettingsSheet.swift` | `case jailbreak` + 列表行 + 两处 switch |
| `Shared/DeepLinkCoordinator.swift` | `SettingsDeepLinkTarget.jailbreak` |
| `Shared/DeepLinkRouter.swift` | `minis://settings/jailbreak`（别名 `content-layer`） |
| `Localizable.xcstrings` | 40 条中译（zh-Hans / zh-Hant） |

---

## 已知限制

- 未在真机验证过编译（本 fork 由 CI 构建，产物未签名）
- `JailbreakSettingsView` 用的是 `Picker`，与工程其它设置页一致；早期版本用 `Stepper`，工程里没有先例
- `MinisTests/Standalone/BubbleSpanTests.swift` 的 `names` 数组没有加入新文件名 —— 那是源码扫描测试，只覆盖 17 个固定的 `AIChatViewModel` extension 文件，不影响编译
