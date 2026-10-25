# Ghostty Glide V1：像素级历史滚动与 TUI 区域滚动改造计划

- 状态：**已获批准，代码移植与自动化构建测试通过；真实图形体验和性能验收仍待完成**
- 日期：2026-10-25
- 仓库：`/Users/star/Workspace/code/ai/ghostty-glide`
- 基线：`cec8b92f1ecd176a20a56aa405021e7ae991b996`（`main`，检查时工作区干净）
- 参考源码：[thdxg/ghostty](https://github.com/thdxg/ghostty)，固定参考提交：`64461d0e2778a7d5a0ea85f04bd8ccfa26e1a1d9`。
- 参考补丁：[`0005-smooth-scroll.patch`](https://github.com/thdxg/ghostty/blob/64461d0e2778a7d5a0ea85f04bd8ccfa26e1a1d9/.github/downstream/0005-smooth-scroll.patch)（已对当前基线通过只读 `git apply --check`）。
- 本文只定义设计与实施计划，不意味着已移植或编译通过。

## 1. Goal / 项目目标

Ghostty Glide 是**保留原版 Ghostty 应用、内核及 UI，仅扩展平滑滚动能力**的轻量 Fork。V1 同时交付：

1. **历史输出（scrollback）**：macOS 触控板的精确 delta 能驱动子字符行（sub-row）的像素级连续滚动，不再等累积到整行才更新画面；复用系统输入事件携带的惯性，不人为叠加滚动惯性/整行缓动。
2. **TUI 区域滚动**：在 alternate screen 上，应用通过终端可识别的滚动操作（例如滚动边距内的 SU/SD、IND/RI）移动区域内容时，渲染器利用区域偏移及离场行缓存（ghost rows）完成短暂动画；包含正确的局部裁剪、位置和命中测试。
3. **可回退**：通过 `smooth-scroll` 开关停用两类功能，回到 Ghostty 原有的滚动显示路径。
4. **持续维护**：尽量不修改 macOS UI 代码，不引入 MacTerm 的外层应用和功能，保持从 `ghostty-org/ghostty` 持续同步的低成本。

### 非目标（必须遵守）

- 不 Fork / 换壳 MacTerm；不实现项目管理、侧边栏、工作区、远程连接器、会话恢复和自定义 SwiftUI 页面。
- 不引入 `0011-smooth-scroll-rows.patch`。该补丁控制**历史输出整行移动缓动并吸附行边界**，与本 V1 的 **TUI 区域动画**不是同一功能。
- 不模拟或替换 macOS 原生的触控板惯性；不增加动画速度、摩擦系数、时长等用户配置。
- 不劫持 TUI 的渲染流程，不通过分析屏幕 diff 来猜测应用自身逐帧重绘造成的运动；不承诺任何 TUI 都能平滑。
- 不为这个功能新建 macOS 设置 UI，不引入全新的动画框架。
- 不大改 Ghostty 终端模型、公开 C API、快捷键行为；没有必要不改 AppKit `scrollWheel` 事件路径。
- 不以生成假测试、虚构 benchmark 结果或“编译可能没问题”代替实际验证。

## 2. Decisions / 已确认设计决策

| 事项 | 决策与原因 |
|---|---|
| 移植源 | 以 `0005-smooth-scroll.patch` 为基准，先原样集成验证，再进行经测试证明安全的必要收敛；该补丁当前对本仓库已通过 `git apply --check` |
| 历史输出 | 触控板精确滚动发布 `Screen.viewport_pixel_offset`；在 `RenderState` 请求 overscan、在 Shader 按像素位移绘制 |
| TUI 区域 | 使用 `Screen.region_scrolls` + `renderer/generic.zig` 中的 `RegionAnim`；复用原有终端 scroll primitive 的事件，保留离场行和区域裁剪 |
| 动画算法 | 保留 MacTerm 的区域指数衰减初始实现（参考时间常数 `0.045s`），先实测再微调，不引入与显示刷新率绑定的累计步长 |
| 命中测试 | 点击、选区、悬停、鼠标报告、光标均基于**实际显示帧**的偏移坐标计算，不能另写一套不一致的近似公式 |
| 配置 | 仅一个公开布尔项 `smooth-scroll`，同时控制历史滚动和 TUI 区域动画；关闭时原生滚动表现应保持一致 |
| 目标平台 | V1 聚焦 macOS Metal 的产物和实测；OpenGL/GTK 修改必须保持可编译且功能关闭时不回归，但不将 GTK 平滑体验作为 V1 发布门槛 |
| 构建与运行 | 保留 Ghostty 原版窗口、分屏、标签页和资源目录。不新建独立项目 |
| 发布策略 | 用户确认后在独立功能分支上分阶段提交，全部验收后再决定合入 `main`；不自动推送、发布或做版本重命名 |

### 默认值约定

- Glide 的 macOS 发行版默认开启 `smooth-scroll = true`，用户可设为 `false`。
- 上游 Ghostty 和非 macOS 默认行为应尽可能保留；若当前配置系统不适合按平台设置默认值，则先采用**明确的最小配置策略**并在实施阶段决定默认值落点，绝不建立 SwiftUI 侧旁路配置。
- 整个 V1 不暴露 `smooth-scroll-rows`，不引入与 `smooth-scroll` 同义的第二个开关。
- 禁用功能必须停止区域动画的后续重绘、清理 pending/ghost 状态，并避免重启时才生效的状态残留；能否热更新，遵守 Ghostty 原有配置热加载能力。

## 3. Rationale / 技术依据

### 3.1 本地验证结论（2026-10-25）

- 本仓库 `main` 的 HEAD 为 `cec8b92f1`，未有未提交改动；当前 `origin` 为 `https://github.com/opentokenz/ghostty-glide.git`，尚未配置 `upstream`。
- `src/Surface.zig:scrollCallback` 已将精确触控板 delta 归一化为像素，并用 `pending_scroll_y` 累加余量，但仅满一行才提交滚动；修改重点应在**将剩余偏移交给渲染器**。
- `src/terminal/render.zig` 已存在 `RenderState.overscan_request` 机制，无需重新设计 terminal row cache。
- `macos/.../SurfaceView_AppKit.swift:scrollWheel` 已发送精确滚动事件及 momentumPhase，且存在原版 2 倍精确 delta 增益。先不改这一逻辑。
- 远程 `0005-smooth-scroll.patch` 在当前 HEAD 上的 `git apply --check` 通过；**只代表 patch 上下文兼容，不代表编译/测试/运行通过**。
- `0011-smooth-scroll-rows.patch` 单独 `git apply --check` 失败，因为依赖 0005；V1 不需要它。
- 已有 Xcode 27.1，终端 PATH 目前没有 `zig`；`build.zig.zon` 声明最低 Zig 为 `0.17.0`。先建立本地 build baseline。
- 上游开发指南建议 macOS 使用 Xcode、SDK、Metal Toolchain，运行 `zig build` 和定向 `zig build test -Dtest-filter=...`。

### 3.2 原版与期望变化

```text
macOS NSEvent
  ├─ 精确 delta + 系统 momentum ─> Surface.scrollCallback
  │   ├─ 整行滚动                      -> Screen.scroll
  │   └─ 不足整行的像素余量             -> Screen.viewport_pixel_offset
  │                                       -> RenderState + overscan
  │                                       -> Metal Shader 像素位移及裁剪
  │
  └─ 应用输出的终端控制序列             -> Terminal.scrollUp/scrollDown/index
                                          -> alternate screen region_scrolls
                                          -> Renderer.RegionAnim
                                          -> 保存离场 ghost rows
                                          -> 更新 region uniforms
                                          -> Metal Shader 区域动画
```

视口历史滚动和 TUI 区域滚动共用一个 `smooth-scroll` 用户开关和现有渲染基础，但**不得把它们混成同一条输入事件路线**。TUI 区域动画由终端屏幕状态变化驱动，不以触控板滚动事件为前提。

### 3.3 TUI 能力边界

补丁的区域滚动事件仅在**alternate screen** 记录；滚动区域由终端的上下左右 margin 决定。区域滚动包括终端 primitive 中被识别的 SU/SD 和边距触发的 IND 等，直接大块清屏或应用重画不是滚动。

典型收益：采用终端滚动操作的 `less`、编辑器、输出浏览器的行滚动和局部区域滚动。Neovim / Vim / Helix 的实际行为取决于版本、配置及其采用的渲染路径。

典型不保证：TUI 使用坐标定位重绘字符、局部矩形逐格更新、复杂动画程序自行刷新帧、mouse-reporting 场景完全由应用处理输入。此时不能强制表现成平滑滚动。

## 4. Scope / 代码范围与模块契约

### 4.1 用户输入和终端状态

- `src/Surface.zig`：保留轮子与触控板归一化/倍率/修饰键/mouse-reporting/alternate-scroll 逻辑；精确滚动时保留像素余量；将像素余量与当前视口行数协作更新，避免方向反转跳变。命中测试使用渲染时确定的偏移。
- `src/terminal/Screen.zig`：保存 `viewport_pixel_offset`、`RegionScroll` / `RegionScrolls`；整行视口跳转需清理已失效的 sub-row offset。
- `src/terminal/Terminal.zig`：只对 alternate screen 的有效滚动区域事件进行记录；同区域事件合并，越界/清屏/无实际位移不生成动画。
- `src/config/Config.zig`：定义、校验、文档化 `smooth-scroll`，不扩散到 SwiftUI 配置。

### 4.2 RenderState 与 Metal 渲染

- `src/terminal/render.zig`：根据渲染 geometry 解析视口偏移，动态请求有效的 overscan 行；位移必须在屏幕边界被正确裁剪。记录可捕获光标相对行，供渲染复用。
- `src/renderer/generic.zig`：复用现有更新/绘制生命周期接管 viewport offset 与区域动画；将同一区域内连续事件叠加进尚未结束的动画；离场行生成、限额、回收和 GPU 上传必须有上界。
- `src/renderer/Metal.zig` / `src/renderer/metal/Frame.zig`：将帧对应的 RegionShifts 与**真正被屏幕展示的渲染目标**关联，避免点击与选区落后于显示帧；注意主线程、GPU completion 和锁顺序。
- `src/renderer/metal/shaders.zig` / `src/renderer/shaders/shaders.metal`：新增 shader uniforms、视口 offset、局部区域偏移/裁剪、ghost rows；文字、背景、光标和图像移动保持一致。
- `src/renderer/opengl/shaders.zig` / `src/renderer/shaders/glsl/*`：若采用完整补丁则应维护 uniform 接口兼容性，保证 GTK/GL 构建不因结构变更失败。
- `src/renderer/cursor.zig`：必要时修正 overscan/滚动中的光标位置，不能引入 cursor shader / cursor trail 功能。

### 4.3 状态/同步不变量

1. **历史滚动边界**：无历史行可供揭示时，不能绘制一条空白区域；到顶/到底的余量不会反复产生抖动。
2. **区域动画边界**：只移动滚动区域矩形内部的内容，区域外不动；移出区域的旧行只在有效区域中作为 ghost 绘制并被及时释放。
3. **区域并发与有界性**：沿用参考补丁对 pending region、并发 RegionAnim 和 ghost rows 的固定容量；超过容量宁可放弃动画，也不能无上限分配或破坏终端状态。
4. **帧一致性**：鼠标命中、URL hover、拖选、mouse-reporting 使用屏幕已呈现或可以安全确定的区域偏移；不能拿“下一帧”的偏移判断“上一帧”的画面。
5. **绘制生命周期**：只有动画在进行时才安排持续 draw；动画趋近结束后停止刷新，不因补丁导致空闲终端永远以高帧率运行。
6. **线程与锁**：保持原 Ghostty render-state mutex / draw mutex 顺序，避免 draw、frame completion、surface hit test 引入锁反序死锁。
7. **切换与尺寸变化**：alternate/primary screen 切换、分屏 resize、字体/行高变化、滚动位置直接跳转、Surface 销毁必须清理过期 viewport/region/ghost 数据。
8. **兼容性**：滚动事件在 mouse-reporting、alternate-scroll 和普通 scrollback 下必须按 Ghostty 原本的分支分发；关闭 smooth-scroll 不修改应用收到的事件序列。

## 5. Alternatives / 方案取舍

| 方案 | 结果 |
|---|---|
| 直接移植完整 0005，先测试再必要收敛 | **采用**：既有区域动画、原生惯性、边界处理、hit-test 与测试，风险相对可控 |
| 从零重写小型像素滚动 | 不采用：易漏掉 overscan / ghost rows / 交互命中 / 锁和帧同步问题 |
| 0005 + 0011 一次移植 | 暂不采用：0011 是 scrollback 的整行吸附缓动，额外延迟与跟手性需要单独论证 |
| 改 AppKit scrollWheel，手工模拟惯性 | 不采用：只会改变输入，不能从 Shader 绘制缺失的上一/下一行 |
| 直接 Fork MacTerm 应用并删除侧边栏 | 不采用：引入另一套 App/SwiftUI 产品层，与“保持 Ghostty 原样”的目标冲突 |

## 6. Implementation Plan / 实施阶段与完成门槛

> 这些是**未来获批后**执行的步骤；此计划阶段不运行构建、下载或应用补丁，不修改产品代码、不创建分支/提交/Release。

### 阶段 A — 基线与工具链

- 记录当前 `origin/main` 的提交、状态与构建版本；新增上游 `upstream=https://github.com/ghostty-org/ghostty.git`（获批后），保留原始 `origin`。
- 准备与该提交兼容的 Zig 0.17.x（实际使用版本需与当前上游指南匹配）、Xcode 和 Metal Toolchain；在原版上通过 `zig build`、相关定向 Zig tests 与原生 macOS 应用启动。
- 记录原版空闲 CPU/GPU、内存、120Hz/60Hz 渲染表现与滚轮/触控板事件行为，不把工具链或上游问题误判为补丁问题。
- 完成门槛：原版可编译、可运行，基线工作负载可复现。

### 阶段 B — 补丁基准移植

- 从 `thdxg/ghostty` 固定参考提交 `64461d0e2778a7d5a0ea85f04bd8ccfa26e1a1d9` 提取 `0005`，校验补丁上下文；在新功能分支应用，并检查全部 hunk，不能仅凭 `git apply --check` 宣称成功。
- **原样先跑**编译和其自带测试，分离“参考补丁问题”“当前上游已改结构”和“Glide 自定义行为”的影响。
- 记录改动文件及必要性，识别补丁中与滚动无关、但为命中测试/渲染互斥性服务的 hunk。只有行为证据足够时才删减，避免在首次移植时重写几千行逻辑。
- 完成门槛：可编译、运行，历史输出和至少一个 alternate-screen region-scroll 用例都能看见动画。

### 阶段 C — 历史输出像素滚动验收

- 核对 precise/non-precise 事件、滚动倍率、正负 offset、整行提交、overscan 捕获和边界裁剪。
- 验证起始无 scrollback、接近顶部/底部、左右方向反转、大量 scrollback、窗口 resize、字体尺寸变化及 macOS 系统惯性；不产生触控板手势以外的额外惯性。
- 将 macOS 构建的 `smooth-scroll` 默认设置为 Glide 期望值，能通过同一开关回到原版。
- 完成门槛：缓慢移动可看到子行连续动画，停手后只保留系统动量，没有额外尾程；配置关闭时行为回退。

### 阶段 D — TUI 区域动画验收

- 测试 alternate screen 的有效滚动事件识别：SU/SD/IND/RI、上下/左右 margin、正反向、上下边界、单/多行、无效高度、一次移除整块区域等。
- 确认同区域连续滚动的动画偏移叠加与中断，新帧使用过去真正可见的行补偿；滚动区域外的 UI 不动。
- 验证 `max_region_anims` 等限额、ghost rows 的缓存回收、多区域同帧、切换 screen、窗口 resize 和字体变化时释放。
- 使用真实 `less`、Vim/Neovim/Helix 等手工案例记录**是否发出了受支持的滚动原语**，按观察结果注明适用性，不将重绘类 TUI 定义为失败。
- 完成门槛：构造的滚动区域测试动画正确；无法识别的应用采用原生重绘，不闪烁、不重复移动、不影响输入和实际屏幕内容。

### 阶段 E — 交互同步、性能与回退

- 检查鼠标点击、文本选择、复制、URL hover、鼠标报告、光标、图片和透明背景；特别关注动画中途点击、拖选与瞬时反转。
- 复查 RegionShifts 针对 Metal 实际显示目标的同步与互斥；反复快速创建/销毁/切换/resize Surface，检查死锁或长期遗留的 GPU/CPU 内存。
- 做 A/B 基线：原版 Ghostty / Glide（开启）/ Glide（关闭），至少各测空闲、长 scrollback 慢滚、快速甩动、TUI 高频连续区域滚动，并覆盖 60Hz、120Hz（具备设备时）。
- 性能目标：交互不卡顿，不出现持续掉帧；动画结束后帧唤醒回归原版闲置逻辑；峰值区域缓存有界。记录实测 frame time p50/p95、GPU/CPU、内存、回收情况；若相同场景性能有明显退化，定位、修复后才能发布，不凭感觉宣布通过。
- 完成门槛：主要验收场景通过、没有未解释的明显性能或稳定性退化、关闭开关能够回退。

### 阶段 F — 收口与上游维护

- 分离提交：上游补丁基准、Glide 默认配置/适配修复、定向测试、产品说明；禁止混入未要求的 MacTerm 功能。
- 记录参考 patch URL / revision、关联的上游提交、必要适配点和变更影响，方便下一次 rebase。
- 对 `upstream/main` 更新先检查 patch 语义/覆盖范围，再运行编译、定向测试和人工滚动验收；上游合并同类能力时优先移除重复实现，而非继续维护两个版本。
- 不自动创建 GitHub Issue/PR，不自动执行 `git push`、发行版命名/签名、打包发布；需要用户单独确认。

## 7. Test Strategy / 测试策略

### 自动单元测试（真实逻辑，针对性优先）

- `Terminal`：仅 alternate-screen 有效区域产生日志/事件；连续事件合并、正反方向、区域高度不足、滚动量超过区域、primary/alternate 不混。
- `RenderState`：正负像素偏移与 overscan 的几何关系；无上下有效邻居时归零；滚动和 resize 后 offset 不越界；屏幕切换时行索引不复用。
- `Surface`：精确滚动余量跨行转换与反向；滚动跳转清理失效余量；mouse-reporting / alternate-scroll 路由不改变。
- `Renderer`：区域动画指数衰减、重复滚动偏移叠加、裁剪矩形、有界 ghost rows、帧偏移命中一致、资源最终释放。
- 对 Shader 的检测以真实运行渲染和相应图像比较/人工核查为准，不造仅测试常量字符串存在的假用例。

### 命令约定（实施阶段）

- `zig build` — 本地 Debug 基线。
- `zig build test -Dtest-filter='<相关用例过滤词>'` — 按项目现有测试名称定向执行。
- `zig build -Demit-macos-app=false` — 只在无需完整 App 的核心验证中加速。
- `git diff --check`、`git status --short` — 代码/提交收口。
- macOS 真实应用运行、包含 ANSI 控制序列的可复现 PTY 场景和手工 TUI 用例 — 交互、图形和帧行为验收。
- 不随意启动长时间全量测试作为每一步的默认动作，但发版前应完成影响范围必要测试。

### 手工验收矩阵

| 场景 | 预期 |
|---|---|
| 慢速触控板浏览历史 | 子行连续位移，无整行跳变 |
| 快速滚动、反转、停手 | 系统动量自然、无额外滚动队列/拖尾 |
| scrollback 顶/底，空历史 | 无露白、无抖动、无负索引 |
| alternate screen 内有效 SU/SD/IND/RI | 区域内的行短暂平滑移动、周围固定 |
| 上下与左右区域边距 | 内容严格裁剪在滚动矩形内 |
| 高频连续区域滚动 / 多区域 | 位移连续，达到容量上限后安全跳过动画 |
| alternate/primary 切换，resize/分屏 | 无残影、错位、空白条带和幽灵缓存 |
| 动画中点击、URL、选区、鼠标报告 | 目标坐标与可见内容相符 |
| `less` / Vim / Neovim / Helix 等 | 按实际使用的滚动原语区分可动画与应用自行重绘，不劫持 TUI 事件 |
| `smooth-scroll=false` | 历史滚动与 TUI 区域均回退原版行为，动画无空闲持续重绘 |
| 空闲、60/120Hz、长时间运行 | 结束动画后停止无意义 draw，无显著回归 |

## 8. Risks / 风险、缓解及回退

1. **补丁规模大**：`0005` 覆盖 17 个文件和多个低层模块。先以完整补丁确认行为，再调整；不应一开始人工重写。
2. **上游更新冲突**：当前 RenderState 已拥有 overscan，后续上游也可能修改动画/帧同步。固定参考版本，回归测试并记录真正必要的 downstream delta。
3. **Metal 显示帧与鼠标命中不一致**：帧完成/呈现、hit testing 位于不同线程。保留补丁中 frame-present 追踪与独立锁的实现意图并测试 lock order。
4. **ghost rows 显存/CPU 分配**：遵守 caps，明确释放时机，繁忙时宁可无动画不能阻塞终端输出。
5. **GPU/功耗**：动画有界结束，缺省无持续自定义 shader；测量空闲状态并限制只为 active animation 唤醒。
6. **TUI 兼容误解**：不承诺自行 repaint 的应用会自动变平滑；文档通过可检测的区域滚动原语定义支持范围。
7. **平台支持**：核心通用补丁影响 OpenGL/GTK；保留编译和回退路径，V1 聚焦 macOS Metal 验收。
8. **故障回退**：功能级通过 `smooth-scroll=false` 立即退出目标行为；代码级按独立提交回退该特性，不用对整个仓库做 `git reset --hard`。

## 9. Acceptance Criteria / 发布门槛

V1 同时满足以下全部条件才算完成：

- [ ] 触控板历史滚动实现真实像素位移，且跟手、自然减速、无额外拖尾。
- [ ] alternate screen 可识别滚动区域获得局部平滑动画；固定区域不动，旧行离场效果与裁剪正确。
- [ ] 原生标签页、分屏、窗口、快捷键、选择与 TUI mouse-reporting 行为无回归。
- [ ] Shader 文本/背景/图片/光标和 hit testing 同步，不产生定位错误、残影和显示撕裂。
- [ ] 动画状态有界、最终被回收，空闲时不持续无用重绘。
- [ ] `smooth-scroll=false` 能恢复原版滚动行为。
- [ ] macOS 完整构建成功，定向 Zig 测试真实通过，至少一次真实 App + TUI 场景检查完成。
- [ ] 源码 diff 限定在滚动功能必要范围，没有 MacTerm 业务 UI、项目管理或无关扩展。
- [ ] 上游同步方式、参考 patch revision、测试结果与已知限制有文档记录。

## 10. Verification / 设计阶段核验（历史记录）

设计阶段确认了 Ghostty 原始基线 `cec8b92f1`、`src/Surface.zig` 的整行滚动余量、`RenderState.overscan_request`、macOS AppKit 精确 delta 输入，以及 MacTerm `0005` 与 `0011` 的功能区别。已对固定提交 `64461d0e2778a7d5a0ea85f04bd8ccfa26e1a1d9` 的 `0005` 执行只读 `git apply --check`，成功。用户随后已明确批准实施。

## 11. Implementation Verification / 实际实施记录

### 已完成并验证

- [x] 创建 `feat/smooth-scroll-v1` 分支，新增官方 `upstream` 远端，`main` 未被修改。
- [x] 完整移植固定参考版本 `0005-smooth-scroll.patch`：17 个源码文件，包含像素历史滚动和 alternate-screen TUI 区域动画；没有引入 `0011` 或 MacTerm 的业务界面。
- [x] 将 Ghostty Glide 的 `smooth-scroll` 默认值设置为 macOS `true`、其他系统 `false`；仍只有一个配置键。
- [x] 安装官方 Zig `0.17.0` 于 `~/.cache/ghostty-glide/toolchains`，Xcode 27.1 的 MetalToolchain 已安装、可调用。
- [x] `zig build test -Dtest-filter="RenderState " -j4`：退出码 0。
- [x] `zig build test -Dtest-filter="Terminal: region scroll noted" -j4`：退出码 0。
- [x] `zig build test -Dtest-filter="PresentedRegions" -j4`：退出码 0。
- [x] `zig build -j4`：退出码 0，生成 `macos/build/Debug/Ghostty.app`（Mach-O arm64/x86_64）。
- [x] `codesign --verify --deep macos/build/Debug/Ghostty.app`：通过。
- [x] 真实 `Ghostty.app/Contents/MacOS/ghostty +show-config --default --no-pager`：输出 `smooth-scroll = true`。
- [x] 使用隔离的 `XDG_CONFIG_HOME` 配置 `smooth-scroll = false` 再运行 CLI：输出 `smooth-scroll = false`。**这是配置解析回退验证，不代替动画运行时回退验收**。
- [x] 11 个修改 Zig 文件的 `zig fmt --check`，`git diff --check`，手动区域回归脚本 `bash -n`：通过。
- [x] 增加 `test/glide-smooth-scroll.sh` 人工可视回归夹具，产生真实 alternate-screen SU、SD 和边距 IND 控制序列；未把它伪称为自动图形测试。
- [x] README 记录 Fork 边界、配置、来源及回归测试入口。临时 GitHub Git 代理已撤销。

### 仍需真实视觉与性能验收

- [ ] 在物理 Mac 图形会话中运行新 Ghostty.app，人工观察触控板慢滚、快速反向、系统惯性尾程和顶部/底部边界。
- [ ] 在新 Ghostty.app 内运行 `bash test/glide-smooth-scroll.sh`，验证上下固定边框不动、TUI 内部 SU/SD/IND 平滑、无残影与离屏剪裁问题。
- [ ] 测试 `less`、Neovim/Vim、Helix 等 TUI，按终端实际控制序列区分能否动画，不承诺应用级自行重绘。
- [ ] 动画中验证选区、光标、图片、超链接及鼠标报告坐标，以及窗口分屏/resize/切屏。
- [ ] 在 60Hz/120Hz、长期空闲、持续滚动场景记录 p50/p95 frame time、CPU/GPU、内存和动画结束后的唤醒次数。
- [ ] 如需发布，还要跑与目标平台对应的必要回归及发布构建。当前 **不宣称达到发布门槛**。

### 环境备注

首次构建因 Zig/本地代理的依赖获取问题与缺失 MetalToolchain 失败；通过隔离 Zig 缓存、官方 MetalToolchain 安装完成。完整 macOS build 的 Xcode 日志仍包含 CoreSimulator 组件版本偏旧警告，但最终 `zig build` 返回 0，产物实际存在、可执行 CLI、代码签名校验成功。CoreSimulator 警告不作为图形运行已验证的证据。

本次只在功能分支上落地，不自动 `git push`、打包发布或替换用户正在使用的 Ghostty 安装。
