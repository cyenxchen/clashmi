# Clash Mi (个人自用版本)

个人自用版本,相比原版区别如下:

## 1. 内核 bridge 切换为开源实现
- 改用同级目录的 `clashmi_vpn_service` 包(基于 gomobile + `cyenxchen/mihomo`)替代原版闭源的 `libclash_vpn_service`。
- 替换了 Dart 侧 import 与 Android 侧自动生成的插件注册;移除了 iOS / macOS / Windows 上闭源 bridge 的生成注册。
- VPN 启动配置补传 IPv6 选项,并在准备阶段输出 core 路径日志,便于启动失败时溯源。

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
