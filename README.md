# dsh

两个自建模块的源码与文档：

| 模块 | 作用 | 入口 |
|---|---|---|
| **手机控制模块**（phone-control） | 在电脑上通过聊天/命令行控制手机：设闹钟、导航、开 App、点按、输入、截屏、执行 shell | [`phone-control/README.md`](phone-control/README.md) |
| **开机动画模块**（bootanimation） | 用 KernelSU 模块替换 ColorOS 开机动画，支持全屏自定义视频 | [`bootanimation/README.md`](bootanimation/README.md) |

详细原理与实现见 [`docs/`](docs/)：

- [手机控制模块说明](docs/手机控制模块.md)
- [开机动画模块说明](docs/开机动画模块.md)

## 目录结构

```
dsh/
├─ docs/
│  ├─ 手机控制模块.md        架构、协议、安装、指令表、安全设计
│  └─ 开机动画模块.md        格式解析、挂载原理、构建流程、踩坑记录
├─ phone-control/
│  ├─ README.md              文件用途表
│  ├─ pc/
│  │  ├─ phone.mjs           电脑端 CLI：签名 → ntfy 下发 → 等回执
│  │  └─ phone-ui.mjs        电脑端 UI 自动化：解析 uiautomator XML 后按文字点击
│  ├─ phone/
│  │  └─ dsh-agent.sh        手机端常驻执行器（Termux + root 权限）
│  └─ modules/
│     └─ dsh-phone-agent-v1.0.7.zip   KernelSU 模块：开机以 root 拉起执行器
└─ bootanimation/
   ├─ README.md              文件用途表
   ├─ bootanimation.zip      最终动画包（ColorOS 私有格式）
   ├─ desc.txt               动画描述文件（g/p 行）
   └─ module/
      ├─ module.prop         KernelSU 模块信息
      └─ post-fs-data.sh     开机后台 bind mount 替换系统动画
```

## 快速开始

### 手机控制

```bash
cd phone-control/pc
node phone.mjs alarm hour=7 minute=20 label="高数 博学楼101"
```

前置：手机装好 Termux + KernelSU 模块（见 `phone-control/README.md`），电脑端准备好 `topic.txt` 与 `hmac.key`（**不入库**）。

### 开机动画

把 `bootanimation/` 打包成 KernelSU 模块刷入，重启即可（见 `bootanimation/README.md`）。

## 安全说明

- 仓库内所有密钥、ntfy topic 均已替换为占位符（`<YOUR_NTFY_TOPIC>` / `<YOUR_HMAC_KEY>`），真实值只存在本机。
- 手机端执行器校验 `sha256(payload + KEY)`，签名不符直接丢弃；时间戳超过 300 秒视为过期。

## 环境

- 电脑：Windows + Node.js ≥ 22
- 手机：Android（ColorOS / OxygenOS 系），已 root（KernelSU），Termux 已安装
