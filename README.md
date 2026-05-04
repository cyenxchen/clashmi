# Clash Mi (个人自用版本)

个人自用版本,相比原版区别如下:

## 1. 内核 bridge 切换为开源实现

**为什么要切换:** 真正的目的是换上自己魔改过的 [`cyenxchen/mihomo`](https://github.com/cyenxchen/mihomo) 内核。原版客户端通过闭源的 `libclash_vpn_service` 把官方 mihomo 内核打包进 bridge,无法替换内核产物;而我自己 fork 的 mihomo 在上游基础上多了几个个人很需要的能力:

- **`url-test` 组支持 `policy-priority`**:可以给匹配特定模式的节点设置延迟权重,实际排序按 `延迟 × 权重` 进行,小于 1 的权重让节点更易胜出。在不放弃自动测速的前提下,优先用自建/低费率节点,只有它们明显劣化时才切走。
- **`select` 组的 `default` 支持通配符**:`default` 除了精确匹配/前缀匹配外,新增 `*` 与 `?` 通配符匹配(精确 > 通配符 > 前缀),启动时可以按模式自动选中默认节点,例如 `default: "JP-*"`。
- **接入 Tailscale  (`type: tailscale`)**:通过内嵌 `tsnet` 把流量直接送入 tailnet,宿主机不需要装 Tailscale 客户端;支持 `auth-key`、`hostname`、`control-url`、`ephemeral`、`accept-routes`、`exit-node` 等配置,完整保留 MagicDNS / split-DNS,TCP 和 UDP 都生效。

要让这些魔改内核真正在 Android 上跑起来,bridge 必须能换成自己用 gomobile 编译的 mihomo 产物——闭源 bridge 做不到,所以整条 bridge 必须切到开源实现。

## 2. 当前仅支持 Android arm64-v8a
- 开源 bridge MVP 只提供 arm64 原生核心,因此 Android 构建与打包限定为 `arm64-v8a`。
- iOS / macOS / Windows / Linux 需要后续补齐对应原生 bridge 实现后才能恢复完整内核运行能力。
- 系统要求中的非 Android 平台暂不可用。

## 3. 应用更新源改为本仓库 GitHub Releases
- 默认更新与下载入口指向 `cyenxchen/clashmi` 的 Releases feed,不再走原版官网。
- 新增解析 GitHub Releases assets 为自动更新模型的逻辑:
  - 过滤非正式 stable tag、AppImage 资产、`.sha256` / 签名等 sidecar 文件。
  - 兼容 Flutter `build name+build number` 的四段版本号与普通三段 tag。
  - 通过分页拉取 GitHub Releases,并避免对 GitHub 请求附加签名 query。
- 增加针对 GitHub Releases 与旧版 JSON 的解析器测试。

---

> 原版项目: <https://github.com/KaringX/clashmi> · 官网: <https://clashmi.app>
